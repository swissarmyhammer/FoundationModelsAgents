import FoundationModels
@testable import FoundationModelsAgents
import FoundationModelsRouter
import Testing

extension NestedRunTests {
    /// Pins the rule of a run whose mail the Router holds
    /// (`SessionEvent.mailDeliveryPaused`): the run does not stop its
    /// children, it waits until each of them ended, and then it ends as
    /// ``AgentRunFailure/mailDeliveryPaused(_:)`` with the held results. A
    /// message from its caller ends the hold, and a cancel cancels its
    /// children.
    ///
    /// The session of the lead has `mailOnlyAnswerLimit` 0: the Router holds
    /// the first final message of a child until user-type mail comes. Each
    /// child waits in a tool on its own gate, thus the test decides the order
    /// in which the children end. The children run on the `flash` slot, and
    /// the lead on the `standard` slot.
    /// The test waits for the recorded state of the lead with
    /// ``NestedRunTests/waitUntil(_:_:)``: the lead calls its idle hook after
    /// it recorded the end of each answer, and in each check of a paused run.
    @Suite("Paused mail")
    struct Pause {
        /// The agent of the temporary layer that starts the children.
        private static let lead = "pause-lead"

        /// The agent of the temporary layer on the `flash` slot.
        private static let child = "pause-child"

        /// The agent files of the temporary layer, by path.
        private static let agentFiles = [
            AgentDocumentPath.of(lead): """
                ---
                name: \(lead)
                description: Gives parts of a task to children.
                tools: Agent(\(child))
                ---

                You are a lead.
                """,
            AgentDocumentPath.of(child): """
                ---
                name: \(child)
                description: Does one part of a task.
                model: flash
                ---

                You are a child.
                """,
        ]

        /// The task prompt of the lead. It is also the key of its play.
        private static let leadKey = "pause-lead-key: divide the task"

        /// The `mailOnlyAnswerLimit` of each session: no answer that mail
        /// alone starts. An answer to mail alone counts toward the limit only
        /// when it starts a new background run. The answers of the lead
        /// start no run, thus a limit of 1 holds no final message here.
        private static let pausedLimit = 0

        /// The message of the host that ends the hold.
        private static let continueMessage = "Continue with the work."

        /// A tool whose body waits on a gate, then gives a fixed output.
        ///
        /// A child waits in a tool call, not in a generation call: a tool
        /// call does not hold the generation queue of the slot. Thus all the
        /// children of the lead can wait at the same time, and the test opens
        /// their gates in its own order.
        struct GateTool: Tool {
            /// The arguments of the tool: one text.
            @Generable
            struct Arguments {
                /// A text that the tool ignores.
                let text: String
            }

            /// The name of the tool.
            let name: String

            /// The description of the tool.
            let description = "A tool that waits until the test opens its gate."

            /// The gate that holds the body.
            let gate: ScriptedGate

            /// Waits on ``gate``, then gives a fixed output.
            ///
            /// - Parameter arguments: The arguments, which the tool ignores.
            /// - Returns: A fixed output.
            /// - Throws: `CancellationError` when the task is cancelled.
            func call(arguments: Arguments) async throws -> String {
                try await gate.wait()
                return "The gate is open."
            }
        }

        /// One child of the lead: its prompt, its final text, and the gate of
        /// its tool.
        private struct Part {
            /// The prompt of the child. It is also the key of its play.
            let key: String

            /// The final text of the child.
            let text: String

            /// The name of the tool of the child.
            let toolName: String

            /// The gate that holds the tool of the child.
            let gate = ScriptedGate()

            /// The play of the child: it calls its tool, which waits on
            /// ``gate``, then it answers ``text``.
            var play: ScriptedAgentPlay {
                ScriptedAgentPlay(
                    key: key,
                    steps: [.toolCall(name: toolName, argumentsJSON: #"{"text": "part"}"#), .finalText(text)])
            }
        }

        /// Makes `count` parts, each with its own key, text, tool, and gate.
        ///
        /// - Parameter count: The count of children.
        /// - Returns: The parts, in start order.
        private static func parts(_ count: Int) -> [Part] {
            (0..<count).map { index in
                Part(
                    key: "pause-child-key-\(index): do part \(index)", text: "Part \(index) is done.",
                    toolName: "pause-gate-\(index)")
            }
        }

        /// Makes the layer and the harness, starts the lead with a play that
        /// starts each child of `parts`, waits until the answer of the task
        /// prompt of the lead ended, and gives the lead to `body`. Then it
        /// deletes the harness and the layer.
        ///
        /// The wait for the task answer comes first: a final message that
        /// comes in that answer is in the same answer, and it is not an
        /// answer to mail alone.
        ///
        /// When `body` throws, for example because the pause did not come,
        /// the function opens each gate and waits until the lead ended. Thus
        /// a test that does not get its pause fails, and it does not hang.
        ///
        /// - Parameters:
        ///   - parts: The children of the lead, in start order.
        ///   - body: Reads the lead.
        /// - Throws: The error of the harness, of the start, or of `body`.
        private static func withLead(parts: [Part], _ body: (AgentRun) async throws -> Void) async throws {
            let layer = try TemporaryLayer.make(holding: agentFiles)
            defer { try? layer.delete() }
            let leadPlay = NestedRunTests.parentPlay(leadKey, children: parts.map { (name: child, prompt: $0.key) })
            let script = ScriptedAgentScript([leadPlay] + parts.map(\.play))
            var tools = ToolCatalog()
            for part in parts {
                tools.register(part.toolName) { GateTool(name: part.toolName, gate: part.gate) }
            }
            let harness = try await AgentRunHarness.make(
                script: script, registry: AgentRegistry(layers: [layer.layer]), tools: tools)
            defer { try? harness.delete() }
            let lead = try await harness.makeRunner(mailOnlyAnswerLimit: pausedLimit).start(Self.lead, prompt: leadKey)
            do {
                try await NestedRunTests.waitUntil(lead) { run in
                    !run.answers.isAnswerOpen && run.answers.lastReply == NestedRunTests.startedText
                }
                try await body(lead)
            } catch {
                for part in parts {
                    part.gate.open()
                }
                _ = await lead.finalState()
                throw error
            }
        }

        /// Gives the one child of `lead` that did not end. Call it at the
        /// hold: the first child ended, and the second waits on its gate.
        ///
        /// - Parameter lead: The lead.
        /// - Returns: The child.
        /// - Throws: The error of `#require` when no child is open, or when
        ///   more than one child is open.
        private static func openChild(of lead: AgentRun) throws -> AgentRun {
            let open = lead.children.runs.filter { $0.state == .running }
            try #require(open.count == 1)
            return try #require(open.first)
        }

        /// Ends the child of `part`, and waits until the lead recorded the
        /// hold of its final message.
        ///
        /// The wait also ends when the lead answered that final message or
        /// ended, because then the Router did not hold the mail. The check
        /// after the wait then fails the test, and the test does not hang.
        ///
        /// - Parameters:
        ///   - part: The part of the child.
        ///   - lead: The lead.
        /// - Throws: `CancellationError` when the test is cancelled, or the
        ///   error of `#require` when the lead is not paused.
        private static func endAndPause(_ part: Part, of lead: AgentRun) async throws {
            part.gate.open()
            try await NestedRunTests.waitUntil(lead) { run in
                run.pause != nil || run.answers.lastReply.contains(part.text) || run.state != .running
            }
            try #require(lead.pause != nil)
        }

        /// Gives the text of a paused failure.
        ///
        /// - Parameter state: The final state of a run.
        /// - Returns: The text, or `nil` for each other state.
        private static func pausedText(of state: AgentRunState) -> String? {
            if case .failed(.mailDeliveryPaused(let text)) = state {
                return text
            }
            return nil
        }

        @Test("a paused run does not stop its open child: it waits for it, then ends with the held results")
        func pausedRunDrains() async throws {
            let parts = Self.parts(2)
            try await Self.withLead(parts: parts) { lead in
                try await Self.endAndPause(parts[0], of: lead)
                let open = try Self.openChild(of: lead)
                let pause = lead.pause
                let report = lead.report

                #expect(open.state == .running)
                #expect(pause?.openChildren == 1)
                #expect(report.contains("It is paused"))

                parts[1].gate.open()
                let text = Self.pausedText(of: await lead.finalState())

                #expect(open.state == .finished(parts[1].text))
                #expect(text?.contains(AgentRun.heldResultsHeading) == true)
                #expect(text?.contains(parts[0].text) == true)
                #expect(text?.contains(parts[1].text) == true)
                #expect(lead.pause == nil)
            }
        }

        /// At limit 0 the final message of the second child is held again
        /// after the answer to the message from the caller. The run then has
        /// no open child, thus it ends paused with that result only.
        @Test("a message from the caller ends the hold, and the run answers the held mail")
        func callerMessageEndsTheHold() async throws {
            let parts = Self.parts(2)
            try await Self.withLead(parts: parts) { lead in
                try await Self.endAndPause(parts[0], of: lead)
                let outcome = try lead.deliver(Self.continueMessage, from: .user)
                try await NestedRunTests.waitUntil(lead) { run in
                    !run.answers.isAnswerOpen && run.answers.lastReply.contains(parts[0].text)
                }
                let pauseAfterMessage = lead.pause
                parts[1].gate.open()
                let text = Self.pausedText(of: await lead.finalState())

                #expect(outcome == .delivered)
                #expect(pauseAfterMessage == nil)
                #expect(text?.contains(parts[1].text) == true)
                #expect(text?.contains(parts[0].text) == false)
            }
        }

        @Test("a cancel of a paused run cancels its open child")
        func cancelDuringTheHold() async throws {
            let parts = Self.parts(2)
            try await Self.withLead(parts: parts) { lead in
                try await Self.endAndPause(parts[0], of: lead)
                let open = try Self.openChild(of: lead)
                lead.cancel()
                let final = await lead.finalState()

                #expect(final == .cancelled)
                #expect(open.state == .cancelled)
            }
        }

        @Test("a pause with no open child ends the run at once with the held result")
        func pauseWithNoOpenChildEndsAtOnce() async throws {
            let parts = Self.parts(1)
            try await Self.withLead(parts: parts) { lead in
                parts[0].gate.open()
                let text = Self.pausedText(of: await lead.finalState())

                #expect(text?.contains(AgentRun.heldResultsHeading) == true)
                #expect(text?.contains(parts[0].text) == true)
            }
        }
    }
}
