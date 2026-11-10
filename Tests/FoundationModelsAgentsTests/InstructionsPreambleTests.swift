import Foundation
@testable import FoundationModelsAgents
import Testing

/// Pins ``AgentEnvironment/instructionsPreamble``: the instructions of each
/// run, a new run and a restored run, start with the preamble, then the
/// `AGENTS.md` text, then the body, then the skill bodies. The instructions
/// of a main session (``AgentRunner/sessionAgentInstructions(for:)`` and
/// ``AgentRunner/defaultAgentInstructions()``) do not hold the preamble: the
/// host adds it to its main session itself.
@Suite("The instructions preamble of a run")
struct InstructionsPreambleTests {
    /// The shared skills and runner of the main-session instructions tests.
    private typealias Fixture = SessionInstructionsFixture

    /// The preamble of the environment.
    private static let preamble = "Preamble: give short answers in Simplified Technical English."

    /// The id of the agent with a `skills:` key.
    private static let agentID = "preamble-agent"

    /// The body of the agent. It has no `$ARGUMENTS`, thus a run and a main
    /// session render it to the same text.
    private static let agentBody = "You do the task of the preamble tests."

    /// The body of the default agent.
    private static let defaultBody = "You are the main session of the preamble tests."

    /// The prompt of each run.
    private static let prompt = "preamble-key: do the task"

    /// The preambles that add no text: no preamble, an empty one, and one
    /// that holds only whitespace.
    private static let emptyPreambles: [String?] = [nil, "", " \n\t "]

    /// The agents, the skills, and the harness of one test.
    private struct Library {
        /// The layer that holds the agents and the skills.
        let layer: TemporaryLayer

        /// The harness over the layer.
        let harness: AgentRunHarness

        /// Deletes the harness and the layer.
        func delete() {
            try? harness.delete()
            try? layer.delete()
        }
    }

    // MARK: - Fixtures

    /// Makes a layer with the default agent and the agent with the `skills:`
    /// key `[Fixture.doTask, Fixture.checklist]`, and a harness over it.
    ///
    /// - Returns: The library. The test deletes it.
    /// - Throws: The error of the file system or of the harness.
    private static func makeLibrary() async throws -> Library {
        let layer = try TemporaryLayer.make(holding: [
            AgentDocumentPath.documentName: Fixture.agentText(
                name: AgentFolderFixture.displayName, body: defaultBody, skills: []),
            AgentFolderFixture.documentPath(of: agentID): Fixture.agentText(
                name: agentID, body: agentBody, skills: [Fixture.doTask, Fixture.checklist])
        ])
        let made = try await Fixture.makeRunner(
            registry: AgentRegistry(layers: [layer.layer]), skills: Fixture.makeSkills(in: layer))
        return Library(layer: layer, harness: made.harness)
    }

    /// Gives the instructions of a run of the agent, over an environment with
    /// `preamble`.
    ///
    /// - Parameters:
    ///   - preamble: The preamble of the environment, or `nil` for none.
    ///   - harness: The harness of the run.
    /// - Returns: The instructions of the run.
    /// - Throws: The failure of the setup, or the error of `#require`.
    private static func runInstructions(preamble: String?, in harness: AgentRunHarness) async throws -> String {
        let environment = harness.environment(
            maxRetainedRuns: AgentEnvironment.defaultMaxRetainedRuns, instructionsPreamble: preamble)
        let setup = try await AgentSessionMaker(
            environment: environment, renderer: AgentBodyRenderer(registry: harness.registry)
        ).resolveSetup(for: harness.request(agentID, prompt: prompt), family: ParentRun.Family())
        return setup.instructions
    }

    /// Gives the parts of the instructions of a run that come after the
    /// preamble: the `AGENTS.md` text, the body, then the skill bodies.
    ///
    /// - Parameter harness: The harness of the run.
    /// - Returns: The parts, in order.
    /// - Throws: The failure of the render, or the error of `#require`.
    private static func partsAfterThePreamble(in harness: AgentRunHarness) async throws -> [String] {
        let definition = try #require(harness.registry.catalog().definition(named: agentID))
        let session = try await harness.makeRunner().sessionAgentInstructions(for: definition)
        try #require(session.skillBodies.count == 2)
        return [AgentRunHarness.agentsMdText, session.body] + session.skillBodies
    }

    // MARK: - A new run

    @Test("a run with a preamble starts with the preamble, then AGENTS.md, then the body, then the skills")
    func preambleComesFirst() async throws {
        let library = try await Self.makeLibrary()
        defer { library.delete() }
        let parts = try await Self.partsAfterThePreamble(in: library.harness)

        let instructions = try await Self.runInstructions(preamble: Self.preamble, in: library.harness)

        #expect(instructions == ([Self.preamble] + parts).joined(separator: AgentSessionMaker.instructionsSeparator))
    }

    @Test("a run with no preamble, or a preamble of only whitespace, has the instructions with no preamble",
          arguments: emptyPreambles)
    func emptyPreambleAddsNothing(preamble: String?) async throws {
        let library = try await Self.makeLibrary()
        defer { library.delete() }
        let parts = try await Self.partsAfterThePreamble(in: library.harness)

        let instructions = try await Self.runInstructions(preamble: preamble, in: library.harness)

        #expect(instructions == parts.joined(separator: AgentSessionMaker.instructionsSeparator))
    }

    // MARK: - A restored run

    @Test("a restored run starts its instructions with the preamble, then the AGENTS.md text")
    func restoredRunGetsThePreamble() async throws {
        let setup = try await RestoredRunFixture.make(deferStart: true, instructionsPreamble: Self.preamble)
        defer { try? setup.harness.delete() }
        let session = try #require(setup.run.heldSession)

        let instructions = ScriptedTranscriptText.instructions(of: await session.transcript)
        await setup.runner.stop()

        #expect(instructions.hasPrefix(
            [Self.preamble, AgentRunHarness.agentsMdText].joined(separator: AgentSessionMaker.instructionsSeparator)))
    }

    // MARK: - A main session

    @Test("sessionAgentInstructions(for:) does not hold the preamble")
    func sessionAgentInstructionsHaveNoPreamble() async throws {
        let library = try await Self.makeLibrary()
        defer { library.delete() }
        let definition = try #require(library.harness.registry.catalog().definition(named: Self.agentID))
        let runner = library.harness.makeRunner(instructionsPreamble: Self.preamble)

        let instructions = try await runner.sessionAgentInstructions(for: definition)

        #expect(!instructions.text.contains(Self.preamble))
    }

    @Test("defaultAgentInstructions() does not hold the preamble")
    func defaultAgentInstructionsHaveNoPreamble() async throws {
        let library = try await Self.makeLibrary()
        defer { library.delete() }
        let runner = library.harness.makeRunner(instructionsPreamble: Self.preamble)

        let instructions = try #require(try await runner.defaultAgentInstructions())

        #expect(instructions.text == Self.defaultBody)
    }
}
