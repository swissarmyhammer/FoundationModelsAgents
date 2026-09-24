import FoundationModelsAgents
import FoundationModelsRouter
import Testing

extension LiveSuites {
    /// The slots of the live profile (plan.md §7, §15).
    ///
    /// - An agent whose `model` is the model reference of the `flash` slot
    ///   runs on the `flash` slot. The `session.json` of its session records
    ///   the slot.
    /// - A run on the `flash` slot and a run on the `standard` slot are in
    ///   operation at the same time. The `standard` run waits in
    ///   ``LiveHoldTool``, and the Router holds the generation gate of a model
    ///   for the whole turn. The `flash` run can finish in that time only when
    ///   the two slots have two gates.
    @Suite("Live slots", .serialized, .timeLimit(LiveProfile.timeLimit))
    struct LiveSlotTests {
        /// The agent whose `model` is the model reference of the `flash`
        /// slot.
        private static let referenceAgent = "flash-by-reference"

        /// The agent on the `standard` slot that waits in ``LiveHoldTool``.
        private static let holdingAgent = "standard-holder"

        /// The agent on the `flash` slot that answers while the other run
        /// waits.
        private static let quickAgent = "flash-quick"

        /// The word that ``referenceAgent`` answers with.
        private static let referenceWord = "KIWI"

        /// The word that ``quickAgent`` answers with.
        private static let quickWord = "GRAPE"

        /// The prompt of each run.
        private static let prompt = "Do your task now."

        @Test("an agent with the model reference of the flash slot runs on the flash slot")
        func flashModelReferenceRunsOnTheFlashSlot() async throws {
            let live = try await LiveProfile.shared.value
            let reference = live.profile.flash.chosen.stringValue
            let agents = [
                LiveAgentFile.path(of: Self.referenceAgent): LiveAgentFile.text(
                    id: Self.referenceAgent,
                    description: "Answers with one fixed word on the flash model.",
                    fields: ["model: \(reference)", LiveAgentFile.disallowedTools()],
                    body: LiveAgentFile.answerBody(word: Self.referenceWord))
            ]

            try await LiveHarness.withHarness(agents: agents) { harness in
                let run = try await harness.runner.start(Self.referenceAgent, prompt: Self.prompt)
                let text = try await run.result()

                #expect(try LiveRecording.session(of: run).slot == .flash)
                #expect(text.localizedCaseInsensitiveContains(Self.referenceWord), "The live answer was: \(text)")
            }
        }

        @Test("a run on the flash slot finishes while a run on the standard slot is in operation")
        func runsOnTwoSlotsOverlap() async throws {
            let hold = LiveHoldTool()
            let agents = [
                LiveAgentFile.path(of: Self.holdingAgent): LiveAgentFile.text(
                    id: Self.holdingAgent,
                    description: "Waits in the hold tool on the standard slot.",
                    fields: ["model: standard", "tools: \(LiveHoldTool.toolName)"],
                    body: LiveAgentFile.toolWordBody(toolName: LiveHoldTool.toolName)),
                LiveAgentFile.path(of: Self.quickAgent): LiveAgentFile.text(
                    id: Self.quickAgent,
                    description: "Answers with one fixed word on the flash slot.",
                    fields: ["model: flash", LiveAgentFile.disallowedTools([LiveHoldTool.toolName])],
                    body: LiveAgentFile.answerBody(word: Self.quickWord))
            ]

            try await LiveHarness.withHarness(agents: agents, tools: [hold]) { harness in
                let holdingRun = try await harness.runner.start(Self.holdingAgent, prompt: Self.prompt)
                try #require(try await hold.waitForArrival(upTo: LiveHoldTool.arrivalTimeout))
                let quickRun = try await harness.runner.start(Self.quickAgent, prompt: Self.prompt)
                let quickText = try await quickRun.result()
                let holdingStateAfterQuickRun = holdingRun.state
                hold.open()
                let holdingText = try await holdingRun.result()

                #expect(holdingStateAfterQuickRun == .running)
                #expect(try LiveRecording.session(of: holdingRun).slot == .standard)
                #expect(try LiveRecording.session(of: quickRun).slot == .flash)
                #expect(
                    quickText.localizedCaseInsensitiveContains(Self.quickWord), "The flash answer was: \(quickText)")
                #expect(
                    holdingText.localizedCaseInsensitiveContains(LiveHoldTool.word),
                    "The standard answer was: \(holdingText)")
            }
        }
    }
}
