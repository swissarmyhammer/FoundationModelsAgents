import FoundationModelsAgents
import FoundationModelsExtras
import FoundationModelsRouter
import Testing

extension LiveSuites {
    /// Slash commands, `cancel agent`, and a live edit on real models
    /// (plan.md §9, §9.4, §15).
    ///
    /// - The slash command of an agent gives the final text of its run.
    /// - `cancel agent` stops a run that writes a long text.
    /// - A live edit of an agent file is used by the next `start agent`,
    ///   while a run of the old definition is still in operation. The old
    ///   run waits in ``LiveHoldTool`` until the new run has finished, and
    ///   then completes with the old definition.
    ///
    /// The host calls the `agents` tool outside of a Router session, thus the
    /// caller of each run is `nil`, and the host can check and cancel it.
    @Suite("Live commands, cancel, and live edit", .serialized, .timeLimit(LiveProfile.timeLimit))
    struct LiveCommandTests {
        /// The agent of the slash command.
        private static let echoAgent = "echo-word"

        /// The word that ``echoAgent`` answers with.
        private static let echoWord = "LEMON"

        /// The agent that writes a long text, for the cancel.
        private static let storyAgent = "storyteller"

        /// The agent of the live edit.
        private static let editedAgent = "edited"

        /// The word of the edited definition of ``editedAgent``.
        private static let newWord = "CHERRY"

        /// The prompt of each run.
        private static let prompt = "Do your task now."

        @Test("a slash command gives the final text of its agent")
        func slashCommandGivesItsResult() async throws {
            let agents = [
                LiveAgentFile.path(of: Self.echoAgent): LiveAgentFile.text(
                    id: Self.echoAgent,
                    description: "Answers with one fixed word.",
                    fields: ["model: flash", LiveAgentFile.disallowedTools()],
                    body: LiveAgentFile.answerBody(word: Self.echoWord))
            ]

            try await LiveHarness.withHarness(agents: agents) { harness in
                let commands = await harness.runner.commands(workingDirectory: harness.workingDirectory)
                let command = try #require(commands.first { $0.name == Self.echoAgent })
                let action = try #require(Self.action(of: command))

                let texts: [String] = try await action(
                    SlashCommand.Invocation(arguments: Self.prompt, workingDirectory: harness.workingDirectory)
                ).reduce(into: []) { texts, text in texts.append(text) }

                let run = try LiveHarness.run(of: Self.echoAgent, in: await harness.runner.runs(caller: nil))
                let text = try #require(texts.first)
                #expect(texts.count == 1)
                #expect(run.state == .finished(text))
                #expect(text.localizedCaseInsensitiveContains(Self.echoWord), "The live answer was: \(text)")
            }
        }

        @Test("cancel agent stops a run")
        func cancelAgentStopsARun() async throws {
            let agents = [
                LiveAgentFile.path(of: Self.storyAgent): LiveAgentFile.text(
                    id: Self.storyAgent,
                    description: "Writes a long story.",
                    fields: [LiveAgentFile.disallowedTools()],
                    body: "Write a story of three thousand words about the sea. Write each word of it.")
            ]

            try await LiveHarness.withHarness(agents: agents) { harness in
                let tool = try await harness.makeAgentsTool()
                _ = try await harness.call(
                    tool, LiveHarness.startOperation, ["name": Self.storyAgent, "prompt": Self.prompt])
                let run = try LiveHarness.run(of: Self.storyAgent, in: await harness.runner.runs(caller: nil))
                _ = try await harness.call(tool, LiveHarness.cancelOperation, ["id": run.id.description])

                await #expect(throws: CancellationError.self) { try await run.result() }
                #expect(run.state == .cancelled)
            }
        }

        @Test("a live edit is used by the next delegation while an old run completes")
        func liveEditIsUsedByTheNextDelegation() async throws {
            let hold = LiveHoldTool()
            let path = LiveAgentFile.path(of: Self.editedAgent)
            let oldBody = LiveAgentFile.toolWordBody(toolName: LiveHoldTool.toolName)
            let newBody = LiveAgentFile.answerBody(word: Self.newWord)
            let oldText = Self.editedAgentText(
                fields: ["model: standard", "tools: \(LiveHoldTool.toolName)"], body: oldBody)
            let newText = Self.editedAgentText(
                fields: ["model: flash", LiveAgentFile.disallowedTools([LiveHoldTool.toolName])], body: newBody)

            try await LiveHarness.withHarness(agents: [path: oldText], tools: [hold], watch: true) { harness in
                let tool = try await harness.makeAgentsTool()
                let start = ["name": Self.editedAgent, "prompt": Self.prompt]
                _ = try await harness.call(tool, LiveHarness.startOperation, start)
                let oldRun = try LiveHarness.run(of: Self.editedAgent, in: await harness.runner.runs(caller: nil))
                try #require(try await hold.waitForArrival(upTo: LiveHoldTool.arrivalTimeout))

                let reloads = harness.registry.onReload
                try LiveSourceTree.write(newText, at: path, in: harness.layerRoot)
                _ = await reloads.first { catalog in
                    catalog.definition(named: Self.editedAgent)?.model == ModelSlot.flash.rawValue
                }
                _ = try await harness.call(tool, LiveHarness.startOperation, start)
                let newRun = try LiveHarness.run(
                    of: Self.editedAgent, in: await harness.runner.runs(caller: nil).filter { $0.id != oldRun.id })
                let newAnswer = try await newRun.result()
                let oldStateAfterNewRun = oldRun.state
                hold.open()
                let oldAnswer = try await oldRun.result()

                let oldSession = try LiveRecording.session(of: oldRun)
                let newSession = try LiveRecording.session(of: newRun)
                #expect(oldStateAfterNewRun == .running)
                #expect(oldSession.slot == .standard)
                #expect(newSession.slot == .flash)
                #expect(oldSession.configuration.instructions?.contains(oldBody) == true)
                #expect(newSession.configuration.instructions?.contains(newBody) == true)
                #expect(
                    oldAnswer.localizedCaseInsensitiveContains(LiveHoldTool.word), "The old answer was: \(oldAnswer)")
                #expect(newAnswer.localizedCaseInsensitiveContains(Self.newWord), "The new answer was: \(newAnswer)")
            }
        }

        /// Gives one text of the file of ``editedAgent``.
        ///
        /// - Parameters:
        ///   - fields: The frontmatter lines after `name` and `description`.
        ///   - body: The body.
        /// - Returns: The text of the file.
        private static func editedAgentText(fields: [String], body: String) -> String {
            LiveAgentFile.text(
                id: editedAgent, description: "Answers with one word that a live edit changes.", fields: fields,
                body: body)
        }

        /// Gives the action of the body of `command`.
        ///
        /// - Parameter command: The command.
        /// - Returns: The action, or `nil` when the body is not `.action`.
        private static func action(
            of command: SlashCommand
        ) -> (@Sendable (SlashCommand.Invocation) -> AsyncThrowingStream<String, Error>)? {
            switch command.body {
            case .action(let action):
                action
            case .prompt, .rendered:
                nil
            }
        }
    }
}
