@testable import FoundationModelsAgents
import MetricsTestKit
import TelemetryTestSupport
import Testing

/// Pins the metrics of each agent run (item C and item 4 of the
/// OpenTelemetry design of 2026-09-28): one count on the run counter and one
/// duration on the run timer for each run that ends, with the agent name and
/// the outcome as dimensions, and the failure kind for a failed run. No
/// dimension holds an id or content.
///
/// Each test runs in a `TelemetryCapture` and gives the metrics factory of
/// the capture to the harness through `AgentEnvironment.metricsFactory`. The
/// pump of a Router session is a detached task, thus only this explicit
/// factory carries the metrics of a child run to the capture. No test
/// bootstraps the metrics system.
@Suite("Agent run metrics")
struct AgentRunMetricsTests {
    /// The dimension keys of the metrics of a run.
    private typealias Dimension = AgentsTelemetry.MetricDimension

    /// The values of the outcome of a run.
    private typealias Outcome = AgentsTelemetry.Outcome

    /// The values of the failure kind of a run.
    private typealias Kind = AgentsTelemetry.FailureKind

    /// The content of the nested test: the task texts and the answers.
    private static let nestedContent = [
        NestedRunTests.leadKey, NestedRunTests.reviewerKey, NestedRunTests.reviewerText
    ]

    /// Gives the dimensions of the metrics of one run.
    ///
    /// - Parameters:
    ///   - agent: The name of the agent of the run.
    ///   - outcome: How the run ended.
    ///   - kind: Why the run failed, or `nil` for a run that did not fail.
    /// - Returns: The dimensions, as `(key, value)` pairs.
    private static func dimensions(
        agent: String, outcome: Outcome, kind: Kind? = nil
    ) -> [(String, String)] {
        let identity = [(Dimension.agentName, agent), (Dimension.outcome, outcome.rawValue)]
        return identity + (kind.map { [(Dimension.failureKind, $0.rawValue)] } ?? [])
    }

    /// Expects that `factory` holds one count on the run counter and one
    /// duration of zero or more on the run timer, each with exactly
    /// `dimensions`.
    ///
    /// `TestMetrics` finds a metric only when its label and its full set of
    /// dimensions are equal to the label and the set of the call. Thus a
    /// metric with one more dimension, for example a run id, is not found.
    ///
    /// - Parameters:
    ///   - factory: The metrics factory of the capture.
    ///   - dimensions: The dimensions of the metrics of the run.
    /// - Throws: The error of `TestMetrics` when the factory has no such
    ///   metric.
    private static func expectOneCountAndOneDuration(
        in factory: TestMetrics, dimensions: [(String, String)]
    ) throws {
        let counter = try factory.expectCounter(AgentsTelemetry.MetricName.runCount, dimensions)
        #expect(counter.totalValue == 1)
        let timer = try factory.expectTimer(AgentsTelemetry.MetricName.runDuration, dimensions)
        #expect(timer.values.count == 1)
        #expect(timer.values.allSatisfy { $0 >= 0 })
    }

    @Test("a finished run counts one time and records one duration, by agent name and outcome",
        .timeLimit(.minutes(1)))
    func finishedRunCountsAndRecordsDuration() async throws {
        let factory = try await TelemetryCapture.run(
            forbidding: [AgentRunTests.prompt, AgentRunTests.finalText]
        ) { context in
            let harness = try await AgentRunHarness.make(
                script: AgentRunTests.script([.finalText(AgentRunTests.finalText)]),
                metricsFactory: context.metricsFactory)
            defer { try? harness.delete() }
            let run = try await harness.start(AgentRunTests.reviewer, prompt: AgentRunTests.prompt)
            _ = try await run.result()
            return context.metricsFactory
        }

        try Self.expectOneCountAndOneDuration(
            in: factory, dimensions: Self.dimensions(agent: AgentRunTests.reviewer, outcome: .finished))
        #expect(factory.counters.count == 1)
        #expect(factory.timers.count == 1)
    }

    @Test("a failed run counts one time and records one duration, with its failure kind",
        .timeLimit(.minutes(1)))
    func failedRunCountsWithItsKind() async throws {
        let factory = try await TelemetryCapture.run(forbidding: [AgentRunTests.prompt]) { context in
            let harness = try await AgentRunHarness.make(
                script: AgentRunTests.script([.fail(NestedRunTests.ScriptedFailure.broken)]),
                metricsFactory: context.metricsFactory)
            defer { try? harness.delete() }
            let run = try await harness.start(AgentRunTests.reviewer, prompt: AgentRunTests.prompt)
            _ = await run.finalState()
            return context.metricsFactory
        }

        try Self.expectOneCountAndOneDuration(
            in: factory,
            dimensions: Self.dimensions(agent: AgentRunTests.reviewer, outcome: .failed, kind: .error))
    }

    @Test("a cancelled run counts one time and records one duration, with no failure kind",
        .timeLimit(.minutes(1)))
    func cancelledRunCounts() async throws {
        let gate = ScriptedGate()
        let factory = try await TelemetryCapture.run(forbidding: [AgentRunTests.prompt]) { context in
            let harness = try await AgentRunHarness.make(
                script: AgentRunTests.script([.wait(gate), .finalText(AgentRunTests.finalText)]),
                metricsFactory: context.metricsFactory)
            defer { try? harness.delete() }
            let run = try await harness.start(AgentRunTests.reviewer, prompt: AgentRunTests.prompt)
            await gate.waitForArrival()
            run.cancel()
            _ = await run.finalState()
            return context.metricsFactory
        }

        try Self.expectOneCountAndOneDuration(
            in: factory, dimensions: Self.dimensions(agent: AgentRunTests.reviewer, outcome: .cancelled))
    }

    @Test("a run whose setup failed counts one time as failed with setupFailed")
    func setupFailureCountsAsFailed() async throws {
        let factory = try await TelemetryCapture.run(forbidding: [AgentRunTests.prompt]) { context in
            let harness = try await AgentRunHarness.make(
                script: AgentRunTests.script([.finalText(AgentRunTests.finalText)]),
                metricsFactory: context.metricsFactory)
            defer { try? harness.delete() }
            let run = try await harness.start(
                NestedRunTests.lead, prompt: AgentRunTests.prompt, agentsTool: { _, _ in throw CancellationError() })
            #expect(run.isSetupFailure)
            return context.metricsFactory
        }

        try Self.expectOneCountAndOneDuration(
            in: factory,
            dimensions: Self.dimensions(agent: NestedRunTests.lead, outcome: .failed, kind: .setupFailed))
    }

    @Test("a start before the first load counts one time as failed with catalogNotLoaded and records no duration")
    func startBeforeLoadCountsWithNoDuration() async throws {
        let factory = try await TelemetryCapture.run(forbidding: [AgentRunTests.prompt]) { context in
            let harness = try await AgentRunHarness.make(
                script: ScriptedAgentScript([]), metricsFactory: context.metricsFactory)
            defer { try? harness.delete() }
            let runner = AgentRunner(
                registry: AgentRegistry(stack: FixtureLibrary.stack()), environment: harness.environment)
            await #expect(throws: AgentRunnerError.catalogNotLoaded) {
                try await runner.start(AgentRunTests.reviewer, prompt: AgentRunTests.prompt)
            }
            return context.metricsFactory
        }

        let counter = try factory.expectCounter(
            AgentsTelemetry.MetricName.runCount,
            Self.dimensions(agent: AgentRunTests.reviewer, outcome: .failed, kind: .catalogNotLoaded))
        #expect(counter.totalValue == 1)
        #expect(factory.counters.count == 1)
        #expect(factory.timers.isEmpty)
    }

    @Test("with no metrics factory in the environment, a run uses MetricsSystem.factory",
        .timeLimit(.minutes(1)))
    func noFactoryUsesTheMetricsSystem() async throws {
        let factory = try await TelemetryCapture.run(
            forbidding: [AgentRunTests.prompt, AgentRunTests.finalText]
        ) { context in
            let harness = try await AgentRunHarness.make(
                script: AgentRunTests.script([.finalText(AgentRunTests.finalText)]))
            defer { try? harness.delete() }
            let run = try await harness.start(AgentRunTests.reviewer, prompt: AgentRunTests.prompt)
            _ = try await run.result()
            return context.metricsFactory
        }

        try Self.expectOneCountAndOneDuration(
            in: factory, dimensions: Self.dimensions(agent: AgentRunTests.reviewer, outcome: .finished))
    }

    @Test("the metrics factory of the environment gets one count and one duration of a parent and of its child",
        .timeLimit(.minutes(1)))
    func parentAndChildCountThroughTheFactoryOfTheEnvironment() async throws {
        let script = ScriptedAgentScript([
            NestedRunTests.parentPlay(
                NestedRunTests.leadKey, children: [(NestedRunTests.reviewer, NestedRunTests.reviewerKey)]),
            ScriptedAgentPlay(key: NestedRunTests.reviewerKey, steps: [.finalText(NestedRunTests.reviewerText)])
        ])
        let factory = try await TelemetryCapture.run(forbidding: Self.nestedContent) { context in
            let harness = try await AgentRunHarness.make(script: script, metricsFactory: context.metricsFactory)
            defer { try? harness.delete() }
            let runner = harness.makeRunner()
            let lead = try await runner.start(NestedRunTests.lead, prompt: NestedRunTests.leadKey)
            _ = try await lead.result()
            let child = try await NestedRunTests.onlyRun(of: runner, caller: lead.id)
            _ = await child.finalState()
            return context.metricsFactory
        }

        for agent in [NestedRunTests.lead, NestedRunTests.reviewer] {
            try Self.expectOneCountAndOneDuration(
                in: factory, dimensions: Self.dimensions(agent: agent, outcome: .finished))
        }
    }
}
