import Metrics

extension AgentEnvironment {
    /// The metrics factory of one run: ``metricsFactory`` when the host gave
    /// one, or `MetricsSystem.factory` at the time of the call.
    ///
    /// A metric keeps the factory of the time that it was made, thus each run
    /// reads the factory and makes its metrics when it ends, never in a
    /// stored value. The package never bootstraps the metrics system.
    internal var runMetricsFactory: any MetricsFactory {
        metricsFactory ?? MetricsSystem.factory
    }

    /// Counts one ended run on the run counter, and records its duration on
    /// the run timer when the run has a duration (item C of the
    /// OpenTelemetry design of 2026-09-28).
    ///
    /// The dimensions are the agent name, the outcome, and the failure kind
    /// of a failed run. Each has a small, fixed set of values, and none is
    /// content. The counter and the timer are made for this call with
    /// ``runMetricsFactory``.
    ///
    /// - Parameters:
    ///   - agent: The name of the agent of the run.
    ///   - outcome: How the run ended.
    ///   - kind: Why the run failed, or `nil` when the run did not fail.
    ///   - duration: The time from the start of the run to its final state,
    ///     or `nil` when no run started and thus no run time exists.
    fileprivate func recordRunMetrics(
        agent: String, outcome: AgentsTelemetry.Outcome, kind: AgentsTelemetry.FailureKind?, duration: Duration?
    ) {
        let factory = runMetricsFactory
        let identity = [
            (AgentsTelemetry.MetricDimension.agentName, agent),
            (AgentsTelemetry.MetricDimension.outcome, outcome.rawValue)
        ]
        let dimensions = identity + (kind.map { [(AgentsTelemetry.MetricDimension.failureKind, $0.rawValue)] } ?? [])
        Counter(label: AgentsTelemetry.MetricName.runCount, dimensions: dimensions, factory: factory).increment()
        guard let duration else {
            return
        }
        Timer(label: AgentsTelemetry.MetricName.runDuration, dimensions: dimensions, factory: factory)
            .recordSeconds(duration / .seconds(1))
    }
}

extension AgentRun {
    /// Counts the run on the run counter and records its duration on the run
    /// timer, with the agent name, the outcome and, for a failed run, the
    /// failure kind as dimensions.
    ///
    /// The run calls this method one time, when it records its final state
    /// (``traced(in:_:)``). A run whose setup failed calls it too, with the
    /// outcome failed and the kind ``AgentsTelemetry/FailureKind/setupFailed``.
    ///
    /// - Parameters:
    ///   - final: The final state of the run.
    ///   - duration: The time from the start of the run to its final state.
    ///   - environment: The environment of the run. It gives the metrics
    ///     factory.
    internal func recordMetrics(of final: AgentRunState, after duration: Duration, in environment: AgentEnvironment) {
        environment.recordRunMetrics(
            agent: agent.id, outcome: AgentsTelemetry.Outcome(final), kind: Self.failureKind(of: final),
            duration: duration)
    }

    /// Gives the failure kind of a final state.
    ///
    /// - Parameter final: The final state of a run.
    /// - Returns: The kind of the failure of a failed run, or `nil` for a run
    ///   that finished or was cancelled.
    private static func failureKind(of final: AgentRunState) -> AgentsTelemetry.FailureKind? {
        guard case .failed(let failure) = final else {
            return nil
        }
        return AgentsTelemetry.FailureKind(failure)
    }
}

extension AgentRunner {
    /// Counts a start before the first load of the registry on the run
    /// counter, with the outcome failed and the failure kind
    /// ``AgentsTelemetry/FailureKind/catalogNotLoaded``.
    ///
    /// The runner starts no run then, thus no duration exists, and the run
    /// timer records nothing. This is the same decision as the failed log
    /// record of ``logStartBeforeLoad(of:)``, which has no duration. The name
    /// of the agent is the name that the host gave: a name, not content.
    ///
    /// - Parameter name: The name of the agent that the host started.
    internal nonisolated func countStartBeforeLoad(of name: String) {
        environment.recordRunMetrics(agent: name, outcome: .failed, kind: .catalogNotLoaded, duration: nil)
    }
}
