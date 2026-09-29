import Logging

extension AgentEnvironment {
    /// Makes the logger of one run: ``logger`` when the host gave one, or a
    /// new `Logger` with the label of the package.
    ///
    /// A logger keeps the handler of the time that it was made, thus each run
    /// makes its logger when it starts, never in a stored value. The package
    /// never bootstraps the logging system.
    ///
    /// - Returns: The logger of the run.
    internal func makeRunLogger() -> Logger {
        logger ?? Logger(label: AgentsTelemetry.logLabel)
    }
}

extension Logger {
    /// Writes the end record of a failed run at `.error` (item B of the
    /// OpenTelemetry design of 2026-09-28).
    ///
    /// The record holds the failure kind and the name of the type of the
    /// error, never the text of the error: the text of a failure can hold the
    /// reply of the model or the output of a tool.
    ///
    /// - Parameters:
    ///   - kind: Why the run failed.
    ///   - error: The error of the run. Only the name of its type goes into
    ///     the record.
    ///   - metadata: The metadata of the run: its ids, its name, its depth,
    ///     and its duration when it has one. No value is content.
    fileprivate func logRunFailure(
        _ kind: AgentsTelemetry.FailureKind, of error: some Error, metadata: Logger.Metadata
    ) {
        var failure = metadata
        failure[AgentsTelemetry.LogMetadataKey.outcome] = .string(AgentsTelemetry.Outcome.failed.rawValue)
        failure[AgentsTelemetry.LogMetadataKey.failureKind] = .string(kind.rawValue)
        failure[AgentsTelemetry.LogMetadataKey.errorType] = .string(String(describing: type(of: error)))
        self.error("\(AgentsTelemetry.LogMessage.runEnded(.failed))", metadata: failure)
    }
}

extension AgentRun {
    /// Writes the start record of the run at `.info`, with the ids, the name
    /// and the depth of the run.
    ///
    /// The "enter" record of the span of the run is a separate record, and
    /// `TracedCall` writes it (``traced(in:_:)``).
    ///
    /// - Parameter logger: The logger of the run.
    internal func logStart(to logger: Logger) {
        logger.info("\(AgentsTelemetry.LogMessage.runStarted)", metadata: identityMetadata)
    }

    /// Writes the end record of the run: finished or cancelled at `.info`,
    /// failed at `.error`. The record has the ids, the name, the depth, the
    /// outcome and the duration of the run. A failed record also has the
    /// failure kind and the name of the type of the failure. No value is
    /// content.
    ///
    /// - Parameters:
    ///   - final: The final state of the run.
    ///   - duration: The time from the start of the run to its final state.
    ///   - logger: The logger of the run.
    internal func logEnd(in final: AgentRunState, after duration: Duration, to logger: Logger) {
        var metadata = identityMetadata
        metadata[AgentsTelemetry.LogMetadataKey.durationSeconds] = .string("\(duration / .seconds(1))")
        guard case .failed(let failure) = final else {
            let outcome = AgentsTelemetry.Outcome(final)
            metadata[AgentsTelemetry.LogMetadataKey.outcome] = .string(outcome.rawValue)
            logger.info("\(AgentsTelemetry.LogMessage.runEnded(outcome))", metadata: metadata)
            return
        }
        logger.logRunFailure(AgentsTelemetry.FailureKind(failure), of: failure, metadata: metadata)
    }
}

extension AgentRunner {
    /// Writes the failed record of a start before the first load of the
    /// registry, with the failure kind
    /// ``AgentsTelemetry/FailureKind/catalogNotLoaded``.
    ///
    /// The runner starts no run then, thus the record has no run id, and no
    /// start record comes before it. The name of the agent is the name that
    /// the host gave: a name, not content.
    ///
    /// - Parameter name: The name of the agent that the host started.
    internal nonisolated func logStartBeforeLoad(of name: String) {
        environment.makeRunLogger().logRunFailure(
            .catalogNotLoaded, of: AgentRunnerError.catalogNotLoaded,
            metadata: [AgentsTelemetry.LogMetadataKey.agentName: .string(name)])
    }
}
