import FoundationModelsExtras
import FoundationModelsRouter
import Foundation
import Testing
import ULID

@testable import FoundationModelsAgents

/// Pins the typed record that `send agent` gives the host: a tool-call attachment with the id
/// of the mail, the direction, and the receiver. The model never sees it, and it holds no
/// message text.
@Suite("The attachment of a sent message")
struct MessageSentAttachmentTests {
    /// The key of the play of the root session. It is its instructions.
    private static let rootKey = "attachment-root-key"

    /// The first prompt of the root session.
    private static let rootPrompt = "Give the work to an agent."

    /// The second prompt of the root session. It causes the `send agent` call.
    private static let followUpPrompt = "Tell the agent one more thing."

    /// The prompt of the lead run. It is also the key of its play.
    private static let leadPrompt = "attachment-lead-key: divide the task"

    /// The message that the root session sends.
    private static let message = "attachment-secret-message"

    /// The fields of the attachment, as the host decodes them.
    private struct Sent: Decodable, Equatable {
        let mailId: String
        let direction: String
        let receiverRunId: String?
        let receiverSessionId: String
    }

    /// The script of the root session and of the lead run.
    private static func script(gate: ScriptedGate, send: ScriptedArguments) -> ScriptedAgentScript {
        ScriptedAgentScript([
            ScriptedAgentPlay(
                key: rootKey,
                steps: [
                    NestedRunTests.startStep(NestedRunTests.lead, prompt: leadPrompt), .finalText("Done."),
                    .deferredToolCall(name: ToolVocabulary.agentsToolName, arguments: send), .finalText("Done."),
                    .finalTextOfLastPrompt
                ]),
            ScriptedAgentPlay(key: leadPrompt, steps: [.wait(gate), .finalText("Task done."), .finalTextOfLastPrompt])
        ])
    }

    @Test("send agent attaches the mail id, the direction and the receiver for the host")
    func sendAgentAttachesTheSentMessage() async throws {
        let gate = ScriptedGate()
        let send = ScriptedArguments()
        let childMail = CallRecord<String>()
        let (attachments, run) = try await AgentsToolHarness.withStartedRun(
            script: Self.script(gate: gate, send: send), rootKey: Self.rootKey, rootPrompt: Self.rootPrompt,
            runEventObserver: { _, output in
                if case .mailDelivered(let id) = output.event { childMail.add(id.value.description) }
            }
        ) { started in
            var stream = await started.root.streamSessionEvents().makeAsyncIterator()
            try #require(await gate.waitForArrival(orEndOf: started.run))
            send.set(AgentsToolArguments.sendAgent(id: started.run.id.description, message: Self.message))
            _ = try await started.root.respond(to: Self.followUpPrompt)
            gate.open()
            _ = await started.run.finalState()
            await started.root.close()
            var found: [ToolCallAttachment] = []
            while let output = await stream.next() {
                if case .toolCallReport(let report) = output.event {
                    found += report.attachments.filter { $0.schemaName == "FoundationModelsAgents.AgentMessageSent" }
                }
            }
            return (found, started.run)
        }

        let attachment = try #require(attachments.first)
        let sent = try JSONDecoder().decode(Sent.self, from: Data(attachment.contentJSON.utf8))
        #expect(attachments.count == 1)
        #expect(attachment.schemaName == "FoundationModelsAgents.AgentMessageSent")
        #expect(sent.direction == "toChild")
        #expect(sent.receiverRunId == run.id.description)
        #expect(childMail.all.contains(sent.mailId))
        #expect(sent.receiverSessionId == run.id.description)
        #expect(!attachment.contentJSON.contains(Self.message))
    }

    @Test("send caller over the mail route attaches the mail id that the host mail route gave")
    func sendCallerAttachesTheSentMessage() async throws {
        let harness = try await AgentRunHarness.make(script: ScriptedAgentScript([]))
        defer { try? harness.delete() }
        let known = MailID()
        let caller = ULID()
        let sender = ULID()
        let runner = harness.makeRunner(callerMail: { _, _, _ in known })
        let context = AgentsToolContext(
            runner: runner, allowedNames: nil, parent: nil,
            callerLink: AgentsToolContext.CallerLink(sessionID: caller, route: .mail), grant: .full)
        let attached = CallRecord<ToolCallAttachment>()
        let bound = ToolContext(
            sessionID: sender, runPlane: RunPlane(), sink: DroppingSink(), tool: ToolVocabulary.agentsToolName,
            op: "send caller", completionToken: "token", isCancelled: { false },
            attachmentSink: { attached.add($0) })

        let answer = await ToolContext.$current.withValue(bound) {
            await context.messageCaller(Self.message, from: sender)
        }

        let attachment = try #require(attached.all.first)
        let sent = try JSONDecoder().decode(Sent.self, from: Data(attachment.contentJSON.utf8))
        #expect(answer == .success(AgentsToolText.messageSentToCaller))
        #expect(attached.all.count == 1)
        #expect(sent.mailId == known.value.description)
        #expect(sent.direction == "toCaller")
        #expect(sent.receiverRunId == nil)
        #expect(sent.receiverSessionId == caller.description)
        #expect(!attachment.contentJSON.contains(Self.message))
    }
}
