import FoundationModelsAgents
import FoundationModelsExtras
import FoundationModelsRouter
import Testing

extension LiveSuites {
    /// Nested runs on real models: the lineage of three sessions (plan.md
    /// §8.2, §9, §15).
    ///
    /// The root session starts the agent ``lead``. The model of `lead` starts
    /// the agent ``leaf``. The `agentSpawn` record of each run names its
    /// parent session, and its `parentToolCallId` is the correlation id of
    /// the final message that the run posts into the transcript of the parent:
    /// the id of the `start agent` call.
    @Suite("Live nested runs", .serialized, .timeLimit(LiveProfile.timeLimit))
    struct LiveNestedTests {
        /// The agent that the root starts. It starts ``leaf``.
        private static let lead = "lead"

        /// The agent that ``lead`` starts.
        private static let leaf = "leaf"

        /// The task that the root gives to ``lead``.
        private static let leadTask = "Start your helper now."

        /// The task that ``lead`` gives to ``leaf``.
        private static let leafTask = "Give your answer now."

        /// The word that ``leaf`` answers with.
        private static let leafWord = "PAPAYA"

        /// The word that ``lead`` answers with after its call.
        private static let leadWord = "STARTED"

        @Test("agentSpawn links three sessions, and parentToolCallId joins to the start agent call")
        func agentSpawnLinksThreeSessions() async throws {
            let agents = try Self.agentFiles()

            try await LiveHarness.withHarness(agents: agents) { harness in
                let root = harness.makeRootSession(tools: [try await harness.makeAgentsTool()])
                _ = try await root.respond(
                    to: try LiveHarness.agentsCallText([
                        "op": LiveHarness.startOperation, "name": Self.lead, "prompt": Self.leadTask
                    ]))
                let lead = try LiveHarness.run(of: Self.lead, in: await harness.runner.runs(caller: root.id))
                _ = try await lead.result()
                let leaf = try LiveHarness.run(of: Self.leaf, in: await harness.runner.runs(caller: lead.id))
                let leafText = try await leaf.result()
                await root.close()

                let rootSpawn = try LiveRecording.session(in: root.recordingDirectory).agentSpawn
                let leadSpawn = try #require(try LiveRecording.session(of: lead).agentSpawn)
                let leafSpawn = try #require(try LiveRecording.session(of: leaf).agentSpawn)
                let leadCalls = try LiveRecording.operationEvents(of: .toolOutput, in: root.recordingDirectory)
                    .filter { $0.correlationID == leadSpawn.parentToolCallId }
                let leadDirectory = try #require(lead.recordingDirectory)
                let leafCalls = try LiveRecording.operationEvents(of: .toolOutput, in: leadDirectory)
                    .filter { $0.correlationID == leafSpawn.parentToolCallId }

                let rootStartAnswers = try LiveRecording.toolAnswers(in: root.recordingDirectory)
                    .filter { $0.contains(lead.id.description) }
                let leadStartAnswers = try LiveRecording.toolAnswers(in: leadDirectory)
                    .filter { $0.contains(leaf.id.description) }

                #expect(rootSpawn == nil)
                #expect(leadSpawn.parentSessionId == root.id)
                #expect(leafSpawn.parentSessionId == lead.id)
                #expect(leadCalls.map(\.tool) == [LiveHarness.agentsToolName])
                #expect(leafCalls.map(\.tool) == [LiveHarness.agentsToolName])
                #expect(leafCalls.map(\.detail) == [leafText])
                #expect(!rootStartAnswers.isEmpty)
                #expect(!leadStartAnswers.isEmpty)
            }
        }

        /// Gives the files of ``lead`` and ``leaf``.
        ///
        /// `lead` inherits the `standard` slot of the root and may start only
        /// `leaf`. `leaf` runs on the `flash` slot, thus it does not wait for
        /// the generation gate that the turn of `lead` holds.
        ///
        /// - Returns: The text of each file, by its path.
        /// - Throws: The error of ``LiveHarness/agentsCallText(_:)``.
        private static func agentFiles() throws -> [String: String] {
            let leadCall = try LiveHarness.agentsCallText([
                "op": LiveHarness.startOperation, "name": leaf, "prompt": leafTask
            ])
            return [
                LiveAgentFile.path(of: lead): LiveAgentFile.text(
                    id: lead,
                    description: "Starts the leaf agent.",
                    fields: ["tools: Agent(\(leaf))"],
                    body: "\(leadCall) After the tool answers, write the single word \(leadWord)."),
                LiveAgentFile.path(of: leaf): LiveAgentFile.text(
                    id: leaf,
                    description: "Answers with one fixed word.",
                    fields: ["model: flash", LiveAgentFile.disallowedTools()],
                    body: LiveAgentFile.answerBody(word: leafWord))
            ]
        }
    }
}
