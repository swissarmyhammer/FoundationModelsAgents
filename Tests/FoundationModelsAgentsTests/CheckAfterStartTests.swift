@testable import FoundationModelsAgents
import FoundationModelsRouter
import Testing

/// Pins `check agent` and `cancel agent` in the pass right after
/// `start agent` (plan.md §9.1, §9.2).
///
/// The Router gives the pending envelope of `start agent` before the body of
/// the call adds its run. A model can read the envelope and call
/// `check agent` or `cancel agent` in its next pass, before the body added
/// the run. Each such call must find the run of the start, and never give
/// the unknown-id corrective or "You have no runs."
///
/// The root session runs on the `standard` slot, and the child run of
/// code-reviewer runs on the `flash` slot. The child waits on a gate, thus
/// it is in operation when the root session calls the tool.
@Suite("check and cancel agent right after start agent")
struct CheckAfterStartTests {
    /// What one root session gave: the answer of its follow-up call, and the
    /// child run with its final state.
    private struct Played {
        /// The answer of the tool call in the pass after `start agent`.
        let answer: String?

        /// The child run that the root session started.
        let run: AgentRun

        /// The final state of the child after the test opened its gate.
        let final: AgentRunState
    }

    /// The agent of the child run.
    private static let reviewer = AgentRunTests.reviewer

    /// The key of the play of the root session. It is its instructions.
    private static let rootKey = "check-after-start-root"

    /// The prompt of the child run. It is also the key of its play.
    private static let childKey = "check-after-start-child: review the parser"

    /// The prompt of the root session.
    private static let rootPrompt = "Give the review to an agent."

    /// The answer of each turn of the root session.
    private static let rootText = "Done."

    /// The final text of the child run.
    private static let childText = "The parser is correct."

    /// The step of the root session that starts the child.
    private static let startStep = ScriptedAgentStep.toolCall(
        name: ToolVocabulary.agentsToolName,
        argumentsJSON: #"{"op": "start agent", "name": "\#(reviewer)", "prompt": "\#(childKey)"}"#)

    /// Plays a root session that starts the child, then makes `followUp` in
    /// the next pass, and gives the answer of `followUp`.
    ///
    /// - Parameter followUp: The tool call of the pass after `start agent`.
    /// - Returns: The answer of `followUp`, the run of the child, and the
    ///   final state of the child after the test opens the gate.
    /// - Throws: The error of the harness, of the session, or of
    ///   `#require` when the root session started no run.
    private static func answer(of followUp: ScriptedAgentStep) async throws -> Played {
        let gate = ScriptedGate()
        let script = ScriptedAgentScript([
            ScriptedAgentPlay(
                key: rootKey, steps: [startStep, followUp, .finalText(rootText), .finalTextOfLastPrompt]),
            ScriptedAgentPlay(key: childKey, steps: [.wait(gate), .finalText(childText)])
        ])
        let harness = try await AgentsToolHarness.make(script: script)
        defer { try? harness.delete() }
        let root = harness.runHarness.profile.standard.makeSession(instructions: rootKey, tools: [harness.tool])

        _ = try await root.respond(to: rootPrompt)
        let answer = harness.runHarness.script.toolOutputs.last
        let run = try #require(
            await harness.runner.runs(caller: root.id).first, "The answer of the tool call: \(answer ?? "none")")
        gate.open()
        let final = await run.finalState()
        await root.close()
        return Played(answer: answer, run: run, final: final)
    }

    @Test("check agent with the completion token in the next pass gives the report of the run",
        .timeLimit(.minutes(1)))
    func checkWithTokenInNextPassGivesReport() async throws {
        let followUp = ScriptedAgentStep.toolCallWithLastToken(
            name: ToolVocabulary.agentsToolName, operation: "check agent")

        let played = try await Self.answer(of: followUp)

        #expect(played.answer?.hasPrefix("\(played.run.subject) is running.") == true)
        #expect(played.final == .finished(Self.childText))
    }

    @Test("check agent with no id in the next pass gives the report of the run",
        .timeLimit(.minutes(1)))
    func checkWithNoIDInNextPassGivesReport() async throws {
        let followUp = ScriptedAgentStep.toolCall(
            name: ToolVocabulary.agentsToolName, argumentsJSON: #"{"op": "check agent"}"#)

        let played = try await Self.answer(of: followUp)

        #expect(played.answer?.hasPrefix("\(played.run.subject) is running.") == true)
        #expect(played.final == .finished(Self.childText))
    }

    /// The body of a `start agent` call for an unknown agent adds no run. The
    /// end of the body ends the wait of `check agent`, thus the check gives
    /// the unknown-id corrective and does not wait for ever.
    @Test("check agent with the token of a start agent call that started no run gives the unknown-id corrective",
        .timeLimit(.minutes(1)))
    func checkWithTokenOfStartWithNoRunGivesCorrective() async throws {
        let script = ScriptedAgentScript([
            ScriptedAgentPlay(
                key: Self.rootKey,
                steps: [
                    .toolCall(
                        name: ToolVocabulary.agentsToolName,
                        argumentsJSON: #"{"op": "start agent", "name": "no-such-agent", "prompt": "Do it."}"#),
                    .toolCallWithLastToken(name: ToolVocabulary.agentsToolName, operation: "check agent"),
                    .finalText(Self.rootText), .finalTextOfLastPrompt
                ])
        ])
        let harness = try await AgentsToolHarness.make(script: script)
        defer { try? harness.delete() }
        let root = harness.runHarness.profile.standard.makeSession(instructions: Self.rootKey, tools: [harness.tool])

        _ = try await root.respond(to: Self.rootPrompt)
        let outputs = harness.runHarness.script.toolOutputs
        let runs = await harness.runner.runs(caller: root.id)
        await root.close()

        let token = try #require(outputs.first.flatMap(ScriptedTranscriptText.completionToken(in:)))
        #expect(outputs.last == "No run has the id \(token). You have no runs.")
        #expect(runs.isEmpty)
    }

    @Test("cancel agent with the completion token in the next pass cancels the run",
        .timeLimit(.minutes(1)))
    func cancelWithTokenInNextPassCancelsRun() async throws {
        let followUp = ScriptedAgentStep.toolCallWithLastToken(
            name: ToolVocabulary.agentsToolName, operation: "cancel agent")

        let played = try await Self.answer(of: followUp)

        #expect(played.answer?.hasPrefix("The cancel of \(played.run.subject) was sent") == true)
        #expect(played.final == .cancelled)
    }
}
