import Foundation
import FoundationModels
@testable import FoundationModelsAgents
import FoundationModelsExtras
import FoundationModelsSkills
import Testing

/// Pins ``AgentEnvironment/runTemplateContext``: the body of each run, a new
/// run and a restored run, its `skills:` preload, and its `skills` tool render
/// with the template context that the host gives for the definition and the
/// resolved tools of the run.
///
/// With no closure, the body renders with the template context of the agent
/// registry, and each skill with the values of the skills registry, as
/// before.
@Suite("The run template context")
struct RunTemplateContextTests {
    /// The id of the agent of the new-run rows.
    private static let agentID = AgentFolderFixture.helperID

    /// The prompt of each new run.
    private static let prompt = "run-context-key: do the task"

    /// The id of the skill with the gated body.
    private static let gatedSkill = "gated-skill"

    /// The plain body of an agent whose `skills:` key loads ``gatedSkill``.
    private static let plainBody = "You load the gated skill."

    /// The arguments of a `use skill` call of ``gatedSkill``.
    private static let useGatedSkill = #"{"op": "use skill", "id": "gated-skill"}"#

    /// The files of a layer whose agent has the gated body.
    private static let gatedAgent = [
        AgentFolderFixture.documentPath(of: agentID): AgentFolderFixture.agentText(
            name: agentID, body: ShellGroupFixture.gatedText)
    ]

    /// The files of a layer whose agent has a plain body and the `skills:`
    /// key `[gatedSkill]`, and the skill itself.
    private static let skillAgent = [
        AgentFolderFixture.documentPath(of: agentID): AgentFolderFixture.agentText(
            name: agentID, body: plainBody, skills: [gatedSkill]),
        SessionInstructionsFixture.skillPath(of: gatedSkill): SessionInstructionsFixture.skillText(
            gatedSkill, body: ShellGroupFixture.gatedText)
    ]

    /// The setup of one new run.
    private struct NewRun {
        /// The instructions of the run.
        let instructions: String

        /// The tools of the run.
        let tools: [any Tool]

        /// The name of the shared `skills` tool of the harness.
        let skillsToolName: String

        /// Calls the `skills` tool of the run.
        ///
        /// - Parameter json: The arguments, as JSON.
        /// - Returns: The text of the call.
        func callSkills(_ json: String) async throws -> String {
            let tool = try #require(tools.first { $0.name == skillsToolName })
            return try await SkillsToolSharingTests.call(tool, with: json)
        }
    }

    /// A definition and the tool names that one closure call got.
    private struct Call: Sendable, Equatable {
        /// The id of the definition.
        let agentID: String

        /// The names of the resolved tools.
        let toolNames: [String]
    }

    /// Gives a closure that records each call and turns the shell group on
    /// or off.
    ///
    /// - Parameters:
    ///   - enabled: The value of `tools.shell.enabled` that the closure gives.
    ///   - calls: The record of the calls.
    /// - Returns: The closure.
    private static func recording(
        enabled: Bool, into calls: CallRecord<Call>
    ) -> AgentEnvironment.RunTemplateContext {
        { definition, toolNames in
            calls.add(Call(agentID: definition.id, toolNames: toolNames))
            return ShellGroupFixture.context(enabled: enabled)
        }
    }

    /// Resolves the setup of a new run of the agent of `files`. The agent
    /// registry and the skills registry both turn the shell group on.
    ///
    /// - Parameters:
    ///   - files: The files of the layer: the agent, and the skills under
    ///     `skills/`.
    ///   - runTemplateContext: The closure of the environment, or `nil`.
    /// - Returns: The setup of the run.
    private static func newRun(
        _ files: [String: String] = gatedAgent, runTemplateContext: AgentEnvironment.RunTemplateContext?
    ) async throws -> NewRun {
        let layer = try TemporaryLayer.make(holding: files)
        defer { try? layer.delete() }
        let skills = SkillsRegistry(
            roots: [layer.root.appendingPathComponent(SessionInstructionsFixture.skillsFolderName, isDirectory: true)],
            mode: .open, templateContext: ShellGroupFixture.context(enabled: true))
        let harness = try await AgentRunHarness.make(
            script: ScriptedAgentScript([]),
            registry: AgentRegistry(layers: [layer.layer], templateContext: ShellGroupFixture.context(enabled: true)),
            skills: skills)
        defer { try? harness.delete() }
        let environment = harness.environment(
            maxRetainedRuns: AgentEnvironment.defaultMaxRetainedRuns, runTemplateContext: runTemplateContext)
        let setup = try await AgentSessionMaker(
            environment: environment, renderer: AgentBodyRenderer(registry: harness.registry)
        ).resolveSetup(for: harness.request(agentID, prompt: prompt), family: ParentRun.Family())
        return NewRun(instructions: setup.instructions, tools: setup.tools, skillsToolName: harness.skillsTool.name)
    }

    // MARK: - A new run

    @Test("a new run renders the off branch when the closure turns the shell group off")
    func aNewRunRendersTheOffBranch() async throws {
        let calls = CallRecord<Call>()

        let run = try await Self.newRun(runTemplateContext: Self.recording(enabled: false, into: calls))

        #expect(run.instructions.hasSuffix(ShellGroupFixture.offText))
    }

    @Test("a new run renders the on branch when the closure turns the shell group on")
    func aNewRunRendersTheOnBranch() async throws {
        let calls = CallRecord<Call>()

        let run = try await Self.newRun(runTemplateContext: Self.recording(enabled: true, into: calls))

        #expect(run.instructions.hasSuffix(ShellGroupFixture.onText))
    }

    @Test("the closure gets the definition of the run and the names of its resolved tools")
    func theClosureGetsTheDefinitionAndTheToolNames() async throws {
        let calls = CallRecord<Call>()

        let run = try await Self.newRun(runTemplateContext: Self.recording(enabled: false, into: calls))

        #expect(calls.all == [Call(agentID: Self.agentID, toolNames: [run.skillsToolName])])
    }

    @Test("with no closure, the body renders with the context of the registry")
    func noClosureKeepsTheRegistryContext() async throws {
        let run = try await Self.newRun(runTemplateContext: nil)

        #expect(run.instructions.hasSuffix(ShellGroupFixture.onText))
    }

    // MARK: - The skills of a run

    @Test("the skills: preload of a run renders each branch from the closure", arguments: [false, true])
    func thePreloadRendersTheBranchOfTheClosure(enabled: Bool) async throws {
        let calls = CallRecord<Call>()

        let run = try await Self.newRun(Self.skillAgent, runTemplateContext: Self.recording(enabled: enabled, into: calls))

        let expected = enabled ? ShellGroupFixture.onText : ShellGroupFixture.offText
        #expect(run.instructions.hasSuffix(
            [Self.plainBody, expected].joined(separator: AgentSessionMaker.instructionsSeparator)))
    }

    @Test("the skills tool of a run renders each branch from the closure", arguments: [false, true])
    func theSkillsToolRendersTheBranchOfTheClosure(enabled: Bool) async throws {
        let calls = CallRecord<Call>()

        let run = try await Self.newRun(Self.skillAgent, runTemplateContext: Self.recording(enabled: enabled, into: calls))

        let expected = enabled ? ShellGroupFixture.onText : ShellGroupFixture.offText
        let unexpected = enabled ? ShellGroupFixture.offText : ShellGroupFixture.onText
        let text = try await run.callSkills(Self.useGatedSkill)
        #expect(text.contains(expected))
        #expect(!text.contains(unexpected))
    }

    @Test("with no closure, the preload and the skills tool use the values of the skills registry")
    func noClosureKeepsTheSkillsRegistryValues() async throws {
        let run = try await Self.newRun(Self.skillAgent, runTemplateContext: nil)

        #expect(run.instructions.hasSuffix(ShellGroupFixture.onText))
        #expect(try await run.callSkills(Self.useGatedSkill).contains(ShellGroupFixture.onText))
    }

    // MARK: - A restored run

    @Test("a restored run renders its body with the context of the closure")
    func aRestoredRunGetsTheContext() async throws {
        let layer = try TemporaryLayer.make(holding: [
            AgentFolderFixture.documentPath(of: AgentRunTests.testWriter): AgentFolderFixture.agentText(
                name: AgentRunTests.testWriter, body: "\(ShellGroupFixture.gatedText) $ARGUMENTS")
        ])
        defer { try? layer.delete() }
        let calls = CallRecord<Call>()
        let setup = try await RestoredRunFixture.make(
            deferStart: true, runTemplateContext: Self.recording(enabled: true, into: calls),
            registry: AgentRegistry(layers: [layer.layer]))
        defer { try? setup.harness.delete() }
        let session = try #require(setup.run.heldSession)

        let instructions = ScriptedTranscriptText.instructions(of: await session.transcript)
        await setup.runner.stop()

        #expect(instructions.contains(ShellGroupFixture.onText))
        #expect(calls.all.map(\.agentID) == [AgentRunTests.testWriter])
    }
}
