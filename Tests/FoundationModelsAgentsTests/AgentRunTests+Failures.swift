import Foundation
import FoundationModels
@testable import FoundationModelsAgents
import Testing

extension AgentRunTests {
    /// Pins each failure of a run: the failures of the setup, which make no
    /// session, and the failures of the turn (plan.md §8, §12).
    @Suite("Agent run failures")
    struct Failures {
        /// Bytes that are not UTF-8 text.
        private static let invalidUTF8: [UInt8] = [0xFF, 0xFE, 0xFD]

        /// The context size of the scripted context overflow.
        private static let overflowContextSize = 100

        /// The token count of the scripted context overflow.
        private static let overflowTokenCount = 150

        /// The agent of the fixture library that can start agents.
        private static let lead = "lead"

        /// The name of the scripted error in the text of a model failure.
        private static let noMatchingPlayName = "noMatchingPlay"

        @Test("a context overflow in the turn fails the run with contextOverflow")
        func contextOverflowFailsRun() async throws {
            let overflow = LanguageModelError.contextSizeExceeded(
                .init(
                    contextSize: Self.overflowContextSize, tokenCount: Self.overflowTokenCount,
                    debugDescription: "scripted context overflow"))
            let harness = try await AgentRunHarness.make(script: AgentRunTests.script([.fail(overflow)]))
            defer { try? harness.delete() }

            let run = try await harness.start(AgentRunTests.reviewer, prompt: AgentRunTests.prompt)
            await #expect(throws: AgentRunFailure.self) {
                try await run.result()
            }

            #expect(Self.isContextOverflow(run.state))
            #expect(run.heldSession == nil)
        }

        @Test("another model error in the turn fails the run with modelFailed")
        func modelErrorFailsRun() async throws {
            let harness = try await AgentRunHarness.make(script: ScriptedAgentScript([]))
            defer { try? harness.delete() }

            let run = try await harness.start(AgentRunTests.reviewer, prompt: AgentRunTests.prompt)
            await #expect(throws: AgentRunFailure.self) {
                try await run.result()
            }

            #expect(Self.modelFailureText(run.state)?.contains(Self.noMatchingPlayName) == true)
            #expect(run.heldSession == nil)
        }

        @Test("an AGENTS.md that is not text fails the run before it makes a session")
        func unreadableAgentsMdFailsRun() async throws {
            let harness = try await AgentRunHarness.make(
                script: AgentRunTests.script([.finalText(AgentRunTests.finalText)]))
            defer { try? harness.delete() }
            try Data(Self.invalidUTF8).write(
                to: harness.workingDirectory.appendingPathComponent(AgentRunHarness.agentsMdName))

            let run = try await harness.start(AgentRunTests.reviewer, prompt: AgentRunTests.prompt)

            #expect(Self.isAgentsMdFailure(run.state))
            #expect(run.recordingDirectory == nil)
            #expect(AgentRunTests.entryNames(in: harness.sessionsDirectory).isEmpty)
        }

        @Test("a factory of the agents tool that throws fails the run before it makes a session")
        func throwingAgentsToolFailsRun() async throws {
            let harness = try await AgentRunHarness.make(
                script: AgentRunTests.script([.finalText(AgentRunTests.finalText)]))
            defer { try? harness.delete() }

            let run = try await harness.start(
                Self.lead, prompt: AgentRunTests.prompt, agentsTool: { _ in throw CancellationError() })

            #expect(Self.isToolsFailure(run.state))
            #expect(run.recordingDirectory == nil)
            #expect(AgentRunTests.entryNames(in: harness.sessionsDirectory).isEmpty)
        }

        /// `true` when `state` failed with ``AgentRunFailure/agentsMdUnreadable(_:)``.
        ///
        /// - Parameter state: The state of a run.
        /// - Returns: `true` for that failure.
        private static func isAgentsMdFailure(_ state: AgentRunState) -> Bool {
            if case .failed(.agentsMdUnreadable) = state { return true }
            return false
        }

        /// `true` when `state` failed with ``AgentRunFailure/toolsFailed(_:)``.
        ///
        /// - Parameter state: The state of a run.
        /// - Returns: `true` for that failure.
        private static func isToolsFailure(_ state: AgentRunState) -> Bool {
            if case .failed(.toolsFailed) = state { return true }
            return false
        }

        /// `true` when `state` failed with ``AgentRunFailure/contextOverflow(_:)``.
        ///
        /// - Parameter state: The state of a run.
        /// - Returns: `true` for that failure.
        private static func isContextOverflow(_ state: AgentRunState) -> Bool {
            if case .failed(.contextOverflow) = state { return true }
            return false
        }

        /// The text of a ``AgentRunFailure/modelFailed(_:)`` state.
        ///
        /// - Parameter state: The state of a run.
        /// - Returns: The text, or `nil` for each other state.
        private static func modelFailureText(_ state: AgentRunState) -> String? {
            if case .failed(.modelFailed(let text)) = state { return text }
            return nil
        }
    }
}
