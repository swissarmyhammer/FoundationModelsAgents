import Foundation
@testable import FoundationModelsAgents
import FoundationModelsExtras
import FoundationModelsRouter
import Synchronization
import Testing

/// Pins one agent run from `start` to its result (plan.md §8, §8.1).
///
/// Each test resolves its own scripted profile, which records to its own
/// temporary folder. A play matches by a key in the prompt of the run. The
/// nested suites `Failures` and `Lineage` pin the failures and the lineage.
@Suite("Agent run")
struct AgentRunTests {
    /// The agent of the fixture library that runs on the `flash` slot and has
    /// no `$ARGUMENTS`.
    static let reviewer = "code-reviewer"

    /// The agent of the fixture library whose body holds `$ARGUMENTS`.
    static let testWriter = "test-writer"

    /// The prompt of each run. It is also the key of the play.
    static let prompt = "run-prompt-key: review the diff"

    /// The final text of each play.
    static let finalText = "The diff is correct."

    /// A text of the body of the project copy of `code-reviewer`.
    private static let reviewerBodyText = "You are a code reviewer."

    /// The id of each agent that a test writes into a temporary layer.
    private static let writtenAgent = "written-agent"

    /// The path of the file of `writtenAgent`, relative to the layer root.
    private static let writtenAgentPath = "agents/\(writtenAgent).md"

    /// The text of the `compactionPrompt` key of a written agent.
    private static let compactionText = "Keep each file name."

    /// A body that the untrusted render refuses: it uses a filter.
    private static let refusedBody = "Name: {{ \"agent\"|uppercase }}."

    /// A script with one play for ``prompt``.
    ///
    /// - Parameter steps: The steps of the play.
    /// - Returns: The script.
    static func script(_ steps: [ScriptedAgentStep]) -> ScriptedAgentScript {
        ScriptedAgentScript([ScriptedAgentPlay(key: prompt, steps: steps)])
    }

    /// The names of the entries in `directory`, or no names when the folder
    /// does not exist.
    ///
    /// - Parameter directory: The folder to list.
    /// - Returns: The names of the entries.
    static func entryNames(in directory: URL) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    }

    /// Reads the `session.json` of the session of `run`.
    ///
    /// - Parameter run: A run that made a session.
    /// - Returns: The decoded parts of the file.
    /// - Throws: The error of `#require` when the run has no recording
    ///   directory, or the error of the read.
    static func sidecar(of run: AgentRun) throws -> RecordedSidecar {
        let directory = try #require(run.recordingDirectory)
        return try RecordedSidecar.read(in: directory)
    }

    /// Gives the text of an agent file with a valid frontmatter, `extraKeys`,
    /// and `body`.
    ///
    /// - Parameters:
    ///   - extraKeys: More frontmatter lines, or the empty string.
    ///   - body: The body of the file.
    /// - Returns: The text of the file.
    private static func agentFile(extraKeys: String, body: String) -> String {
        """
        ---
        name: \(writtenAgent)
        description: An agent of a test.
        \(extraKeys)
        ---
        \(body)
        """
    }

    /// Makes a registry over one temporary layer that holds `writtenAgent`.
    ///
    /// - Parameters:
    ///   - text: The text of the agent file.
    ///   - source: The source of the layer. The trust comes from it.
    /// - Returns: The temporary layer and the registry over it.
    /// - Throws: The error of the file system.
    private static func writtenRegistry(
        _ text: String, source: DotfolderStack.Source
    ) throws -> (layer: TemporaryLayer, registry: AgentRegistry) {
        let layer = try TemporaryLayer.makeEmpty()
        try layer.write(text, at: writtenAgentPath)
        let registry = AgentRegistry(layers: [DotfolderStack.Layer(source: source, root: layer.root)])
        return (layer, registry)
    }

    /// Reads `events` to its end.
    ///
    /// `close()` of a session finishes each subscription of
    /// `streamSessionEvents()`. A subscription of an open session does not
    /// end, thus the time limit of the test fails it.
    ///
    /// - Parameter events: A subscription of the session events.
    /// - Returns: `true` when the subscription ended.
    private static func ends(_ events: AsyncStream<SessionEvent>) async -> Bool {
        for await _ in events {}
        return true
    }

    /// `true` when `state` failed with ``AgentRunFailure/bodyRenderFailed(_:)``.
    ///
    /// - Parameter state: The state of a run.
    /// - Returns: `true` for that failure.
    private static func isBodyRenderFailure(_ state: AgentRunState) -> Bool {
        if case .failed(.bodyRenderFailed) = state { return true }
        return false
    }

    @Test("a scripted code-reviewer run finishes with the final text on the flash slot")
    func reviewerFinishesOnFlash() async throws {
        let harness = try await AgentRunHarness.make(script: Self.script([.finalText(Self.finalText)]))
        defer { try? harness.delete() }

        let run = try await harness.start(Self.reviewer, prompt: Self.prompt)
        let result = try await run.result()

        #expect(result == Self.finalText)
        #expect(run.state == .finished(Self.finalText))
        #expect(run.slot == .flash)
        #expect(try Self.sidecar(of: run).slot == .flash)
        #expect(run.agent.id == Self.reviewer)
        #expect(run.caller == nil)
        #expect(run.depth == 1)
        #expect(run.heldSession == nil)
    }

    @Test("the run id is the session id, and the recording is at <recordingsDir>/<routerId>/<run.id>")
    func idIsSessionIdAndNamesRecording() async throws {
        let gate = ScriptedGate()
        let harness = try await AgentRunHarness.make(
            script: Self.script([.wait(gate), .finalText(Self.finalText)]))
        defer { try? harness.delete() }

        let run = try await harness.start(Self.reviewer, prompt: Self.prompt)
        let session = try #require(run.heldSession)

        #expect(run.id == session.id)
        #expect(run.recordingDirectory == session.recordingDirectory)
        #expect(
            run.recordingDirectory
                == harness.sessionsDirectory.appendingPathComponent(run.id.description, isDirectory: true))
        #expect(Self.entryNames(in: harness.sessionsDirectory).contains(run.id.description))
        gate.open()
        #expect(try await run.result() == Self.finalText)
    }

    @Test("the id exists when start returns, before the gated turn ends")
    func idExistsBeforeTurnEnds() async throws {
        let gate = ScriptedGate()
        let harness = try await AgentRunHarness.make(
            script: Self.script([.wait(gate), .finalText(Self.finalText)]))
        defer { try? harness.delete() }

        let run = try await harness.start(Self.reviewer, prompt: Self.prompt)
        let id = run.id
        await gate.waitForArrival()

        #expect(run.state == .running)
        #expect(run.heldSession?.id == id)
        gate.open()
        #expect(try await run.result() == Self.finalText)
        #expect(run.id == id)
    }

    @Test("a body render failure fails the run with an id, no session, and no recording")
    func renderFailureMakesNoSession() async throws {
        let written = try Self.writtenRegistry(
            Self.agentFile(extraKeys: "", body: Self.refusedBody), source: .user)
        defer { try? written.layer.delete() }
        let harness = try await AgentRunHarness.make(
            script: Self.script([.finalText(Self.finalText)]), registry: written.registry)
        defer { try? harness.delete() }

        let run = try await harness.start(Self.writtenAgent, prompt: Self.prompt)
        let other = try await harness.start(Self.writtenAgent, prompt: Self.prompt)
        await #expect(throws: AgentRunFailure.self) {
            try await run.result()
        }

        #expect(Self.isBodyRenderFailure(run.state))
        #expect(run.id != other.id)
        #expect(run.heldSession == nil)
        #expect(run.recordingDirectory == nil)
        #expect(run.slot == nil)
        #expect(Self.entryNames(in: harness.sessionsDirectory).isEmpty)
        #expect(harness.script.prompts.isEmpty)
    }

    @Test("the instructions hold the AGENTS.md text first, then the body")
    func instructionsHoldAgentsMdThenBody() async throws {
        let harness = try await AgentRunHarness.make(script: Self.script([.finalText(Self.finalText)]))
        defer { try? harness.delete() }

        let run = try await harness.start(Self.reviewer, prompt: Self.prompt)
        _ = try await run.result()
        let instructions = try #require(try Self.sidecar(of: run).configuration.instructions)
        let agentsMdRange = try #require(instructions.range(of: AgentRunHarness.agentsMdText))
        let bodyRange = try #require(instructions.range(of: Self.reviewerBodyText))

        #expect(instructions.hasPrefix(AgentRunHarness.agentsMdText))
        #expect(agentsMdRange.upperBound <= bodyRange.lowerBound)
    }

    @Test(
        "the first user prompt of the session is the prompt, with or without $ARGUMENTS",
        arguments: [reviewer, testWriter])
    func firstPromptIsThePrompt(agent: String) async throws {
        let harness = try await AgentRunHarness.make(script: Self.script([.finalText(Self.finalText)]))
        defer { try? harness.delete() }
        let definition = try #require(harness.registry.catalog().definition(named: agent))

        let run = try await harness.start(agent, prompt: Self.prompt)
        _ = try await run.result()

        #expect(harness.script.prompts == [Self.prompt])
        #expect(
            definition.body.contains(AgentBodyRenderer.argumentsPlaceholder) == (agent == Self.testWriter))
    }

    @Test("the frontmatter compactionPrompt reaches makeSession")
    func frontmatterCompactionPromptReachesSession() async throws {
        let written = try Self.writtenRegistry(
            Self.agentFile(extraKeys: "compactionPrompt: \(Self.compactionText)", body: Self.reviewerBodyText),
            source: .user)
        defer { try? written.layer.delete() }
        let harness = try await AgentRunHarness.make(
            script: Self.script([.finalText(Self.finalText)]), registry: written.registry)
        defer { try? harness.delete() }
        let definition = try #require(harness.registry.catalog().definition(named: Self.writtenAgent))
        let expected = try #require(definition.compactionPrompt)

        let run = try await harness.start(Self.writtenAgent, prompt: Self.prompt)
        _ = try await run.result()
        let recorded = try Self.sidecar(of: run).configuration

        #expect(expected.text == Self.compactionText)
        #expect(recorded.compactionPrompt == expected)
    }

    @Test("with no compactionPrompt key, the default prompt reaches makeSession")
    func defaultCompactionPromptReachesSession() async throws {
        let harness = try await AgentRunHarness.make(script: Self.script([.finalText(Self.finalText)]))
        defer { try? harness.delete() }

        let run = try await harness.start(Self.reviewer, prompt: Self.prompt)
        _ = try await run.result()
        let recorded = try Self.sidecar(of: run).configuration

        #expect(run.agent.compactionPrompt == nil)
        #expect(recorded.compactionPrompt == .default)
    }

    @Test("environment.budget gets the context of the model")
    func budgetGetsModelContext() async throws {
        let seen = Mutex<[Int]>([])
        let harness = try await AgentRunHarness.make(
            script: Self.script([.finalText(Self.finalText)]),
            budget: { contextTokens in
                seen.withLock { $0.append(contextTokens) }
                return TokenBudget(limit: contextTokens)
            })
        defer { try? harness.delete() }

        let run = try await harness.start(Self.reviewer, prompt: Self.prompt)
        _ = try await run.result()
        let recorded = try Self.sidecar(of: run).configuration
        let contextTokens = harness.profile.flash.contextTokens

        #expect(seen.withLock { $0 } == [contextTokens])
        #expect(recorded.budget == TokenBudget(limit: contextTokens))
    }

    @Test("cancel() during a gated turn gives .cancelled and closes the session", .timeLimit(.minutes(1)))
    func cancelDuringTurnClosesSession() async throws {
        let gate = ScriptedGate()
        let harness = try await AgentRunHarness.make(
            script: Self.script([.wait(gate), .finalText(Self.finalText)]))
        defer { try? harness.delete() }
        let run = try await harness.start(Self.reviewer, prompt: Self.prompt)
        let session = try #require(run.heldSession)
        let sessionEvents = await session.streamSessionEvents()
        await gate.waitForArrival()

        run.cancel()

        await #expect(throws: CancellationError.self) {
            try await run.result()
        }
        #expect(run.state == .cancelled)
        #expect(run.heldSession == nil)
        #expect(await Self.ends(sessionEvents))
    }
}
