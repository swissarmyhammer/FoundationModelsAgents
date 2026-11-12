import Foundation
import Logging
@testable import FoundationModelsAgents
import FoundationModelsExtras
import FoundationModelsRouter
import FoundationModelsSkills
import ULID

/// A restored run of a finished first life, with the host closures recorded. The suites of the
/// restore share it, thus the setup lives in one place.
struct RestoredRunFixture {
    /// One call of the claim completion closure.
    struct ClaimCall: Sendable, Equatable {
        let caller: ULID
        let key: RunKey
        let outcome: OperationOutcome
    }

    /// The error of a mark closure that fails.
    struct MarkFailed: Error {}

    /// The first prompt of the first life, and the key of its play.
    static let originalKey = "restored-fixture-key"

    let harness: AgentRunHarness
    let runner: AgentRunner
    let run: AgentRun
    let child: RecordedChild
    let mails: CallRecord<String>
    let claims: CallRecord<ClaimCall>
    let marks: CallRecord<SessionEndReason>

    /// Restores a run of a finished first life.
    ///
    /// - Parameters:
    ///   - sessionEnding: A mark closure that replaces the recording one, or `nil`.
    ///   - callerMail: A mail closure that replaces the recording one, or `nil`.
    ///   - claimResult: What the claim completion closure answers, or `nil` for no closure.
    ///   - markFails: `true` when the mark closure throws.
    ///   - gate: A gate in the restored life, or `nil`.
    ///   - deferStart: `true` to hold the start of the restored run.
    ///   - markGate: A gate that the mark closure waits on, or `nil`.
    ///   - maxDepth: The depth limit of the runner.
    ///   - logger: The logger of the runs, or `nil`.
    ///   - instructionsPreamble: The preamble of the instructions of the restored life, or `nil`.
    ///     The first life has no preamble.
    ///   - runTemplateContext: The run template context of the restored life, or `nil`. The first
    ///     life has none.
    ///   - registry: The registry of the agents, or `nil` for the fixture library. It must hold
    ///     the agent `AgentRunTests.testWriter`.
    ///   - skills: The skills registry of both lives, or `nil` for an empty one.
    ///   - restoredSteps: The steps of the restored life before its last answer. The default
    ///     gives one text answer.
    ///   - tools: The tool catalog of both lives. The default is an empty catalog.
    static func make(
        sessionEnding: AgentEnvironment.SessionEnding? = nil, callerMail: AgentEnvironment.CallerMail? = nil,
        claimResult: Bool? = nil, markFails: Bool = false, gate: ScriptedGate? = nil, deferStart: Bool = false,
        markGate: ScriptedGate? = nil, maxDepth: Int = AgentEnvironment.defaultMaxDepth, logger: Logger? = nil,
        instructionsPreamble: String? = nil, runTemplateContext: AgentEnvironment.RunTemplateContext? = nil,
        registry: AgentRegistry? = nil, skills: SkillsRegistry? = nil,
        restoredSteps: [ScriptedAgentStep] = [.finalText("restored text")], tools: ToolCatalog = ToolCatalog()
    ) async throws -> RestoredRunFixture {
        let gateSteps: [ScriptedAgentStep] = gate.map { [.wait($0)] } ?? []
        let harness = try await AgentRunHarness.make(
            script: ScriptedAgentScript([
                ScriptedAgentPlay(
                    key: originalKey,
                    steps: [.finalText("first")] + gateSteps + restoredSteps + [.finalTextOfLastPrompt])
            ]), registry: registry ?? AgentRegistry(stack: FixtureLibrary.stack()),
            skills: skills ?? SkillsRegistry.makeEmpty(), tools: tools, logger: logger)
        let original = try await harness.makeRunner().start(AgentRunTests.testWriter, prompt: originalKey)
        _ = try await original.result()
        precondition(
            sessionEnding == nil || (!markFails && markGate == nil),
            "markFails and markGate only shape the recording mark closure")
        let mails = CallRecord<String>()
        let marks = CallRecord<SessionEndReason>()
        let built = Self.makeRunner(
            harness, maxDepth: maxDepth, claimResult: claimResult,
            callerMail: callerMail ?? { message, _, _ in mails.add(message); return MailID() },
            sessionEnding: sessionEnding ?? { _, reason in
                try await Self.markRecording(reason, gate: markGate, fails: markFails, into: marks)
            }, instructionsPreamble: instructionsPreamble, runTemplateContext: runTemplateContext)
        let runner = built.runner
        let claims = built.claims
        let child = RecordedChild(
            sessionID: original.id, agentID: AgentRunTests.testWriter, agentName: nil, parentSessionId: ULID(),
            parentToolCallId: "restored-fixture-token", ended: nil, firstPrompt: originalKey)
        let run = try await runner.restore(child, deferStart: deferStart)
        return RestoredRunFixture(
            harness: harness, runner: runner, run: run, child: child, mails: mails, claims: claims, marks: marks)
    }

    /// Makes a runner whose claim completion closure records each call.
    ///
    /// - Parameters:
    ///   - harness: The harness that holds the registry.
    ///   - maxDepth: The depth limit of the runner.
    ///   - claimResult: What the claim completion closure answers, or `nil` for no closure.
    ///   - callerMail: The mail closure, or `nil` for none.
    ///   - sessionEnding: The mark closure, or `nil` for none.
    ///   - instructionsPreamble: The preamble of the instructions of each run, or `nil` for none.
    ///   - runTemplateContext: The run template context of each run, or `nil` for none.
    /// - Returns: The runner and the record of the claim calls.
    static func makeRunner(
        _ harness: AgentRunHarness, maxDepth: Int = AgentEnvironment.defaultMaxDepth, claimResult: Bool? = true,
        callerMail: AgentEnvironment.CallerMail? = nil,
        sessionEnding: AgentEnvironment.SessionEnding? = { _, _ in }, instructionsPreamble: String? = nil,
        runTemplateContext: AgentEnvironment.RunTemplateContext? = nil
    ) -> (runner: AgentRunner, claims: CallRecord<ClaimCall>) {
        let claims = CallRecord<ClaimCall>()
        var environment = harness.environment(
            maxRetainedRuns: AgentEnvironment.defaultMaxRetainedRuns, maxDepth: maxDepth, callerMail: callerMail,
            sessionEnding: sessionEnding, instructionsPreamble: instructionsPreamble,
            runTemplateContext: runTemplateContext)
        if let claimResult {
            environment = environment.withClaimCompletion { caller, key, outcome, _ in
                claims.add(ClaimCall(caller: caller, key: key, outcome: outcome))
                return claimResult
            }
        }
        return (AgentRunner(registry: harness.registry, environment: environment), claims)
    }

    /// The mark closure that records the reason, after it waits on a gate or fails when asked.
    private static func markRecording(
        _ reason: SessionEndReason, gate: ScriptedGate?, fails: Bool, into marks: CallRecord<SessionEndReason>
    ) async throws {
        if let gate { try? await gate.wait() }
        if fails { throw MarkFailed() }
        marks.add(reason)
    }
}
