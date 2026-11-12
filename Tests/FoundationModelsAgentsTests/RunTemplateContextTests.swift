import Foundation
@testable import FoundationModelsAgents
import FoundationModelsExtras
import Testing

/// Pins ``AgentEnvironment/runTemplateContext``: the body of each run, a new
/// run and a restored run, renders with the template context that the host
/// gives for the definition and the resolved tools of the run.
///
/// With no closure, the body renders with the template context of the
/// registry, as before.
@Suite("The run template context")
struct RunTemplateContextTests {
    /// The id of the agent of the new-run rows.
    private static let agentID = AgentFolderFixture.helperID

    /// A body that tells if the shell group is on.
    private static let gatedText = "{% if tools.shell.enabled %}shell on{% else %}shell off{% endif %}"

    /// The prompt of each new run.
    private static let prompt = "run-context-key: do the task"

    /// A definition and the tool names that one closure call got.
    private struct Call: Sendable, Equatable {
        /// The id of the definition.
        let agentID: String

        /// The names of the resolved tools.
        let toolNames: [String]
    }

    /// Gives a template context with the shell group on or off.
    ///
    /// - Parameter enabled: The value of `tools.shell.enabled`.
    /// - Returns: The context.
    private static func shellContext(enabled: Bool) -> [String: TemplateValue] {
        ["tools": .dictionary(["shell": .dictionary(["enabled": .bool(enabled)])])]
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
            return shellContext(enabled: enabled)
        }
    }

    /// Resolves the setup of a new run of the gated agent, over a registry
    /// whose context turns the shell group on.
    ///
    /// - Parameter runTemplateContext: The closure of the environment, or
    ///   `nil`.
    /// - Returns: The instructions of the run, and the name of the `skills`
    ///   tool of the harness.
    private static func newRun(
        runTemplateContext: AgentEnvironment.RunTemplateContext?
    ) async throws -> (instructions: String, skillsToolName: String) {
        let layer = try TemporaryLayer.make(holding: [
            AgentFolderFixture.documentPath(of: agentID): AgentFolderFixture.agentText(name: agentID, body: gatedText)
        ])
        defer { try? layer.delete() }
        let harness = try await AgentRunHarness.make(
            script: ScriptedAgentScript([]),
            registry: AgentRegistry(layers: [layer.layer], templateContext: shellContext(enabled: true)))
        defer { try? harness.delete() }
        let environment = harness.environment(
            maxRetainedRuns: AgentEnvironment.defaultMaxRetainedRuns, runTemplateContext: runTemplateContext)
        let setup = try await AgentSessionMaker(
            environment: environment, renderer: AgentBodyRenderer(registry: harness.registry)
        ).resolveSetup(for: harness.request(agentID, prompt: prompt), family: ParentRun.Family())
        return (setup.instructions, harness.skillsTool.name)
    }

    // MARK: - A new run

    @Test("a new run renders the off branch when the closure turns the shell group off")
    func aNewRunRendersTheOffBranch() async throws {
        let calls = CallRecord<Call>()

        let run = try await Self.newRun(runTemplateContext: Self.recording(enabled: false, into: calls))

        #expect(run.instructions.hasSuffix("shell off"))
    }

    @Test("a new run renders the on branch when the closure turns the shell group on")
    func aNewRunRendersTheOnBranch() async throws {
        let calls = CallRecord<Call>()

        let run = try await Self.newRun(runTemplateContext: Self.recording(enabled: true, into: calls))

        #expect(run.instructions.hasSuffix("shell on"))
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

        #expect(run.instructions.hasSuffix("shell on"))
    }

    // MARK: - A restored run

    @Test("a restored run renders its body with the context of the closure")
    func aRestoredRunGetsTheContext() async throws {
        let layer = try TemporaryLayer.make(holding: [
            AgentFolderFixture.documentPath(of: AgentRunTests.testWriter): AgentFolderFixture.agentText(
                name: AgentRunTests.testWriter, body: "\(Self.gatedText) $ARGUMENTS")
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

        #expect(instructions.contains("shell on"))
        #expect(calls.all.map(\.agentID) == [AgentRunTests.testWriter])
    }
}
