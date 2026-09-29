import FoundationModelsExtras
import Logging
import Tracing

/// The error that the span of a failed run records: the failure kind, and
/// nothing more.
///
/// The text of an ``AgentRunFailure`` can hold content: the reply of the
/// model, the description of a render error, or the text of a model error.
/// A span leaves the process through the tracing backend of the host, thus
/// the span records this error in place of the failure. Its description is
/// the raw value of the kind.
internal struct AgentRunSpanFailure: Error, CustomStringConvertible {
    /// Why the run failed.
    internal let kind: AgentsTelemetry.FailureKind

    /// The raw value of ``kind``. It carries no content.
    internal var description: String {
        kind.rawValue
    }
}

extension AgentsTelemetry.Outcome {
    /// Gives the outcome of a final state.
    ///
    /// A run records its outcome only at its final state. ``AgentRunState``
    /// ``AgentRunState/running`` does not occur there. It gives
    /// ``cancelled``, as ``AgentRun/result()`` reads it.
    ///
    /// - Parameter final: The final state of a run.
    internal init(_ final: AgentRunState) {
        switch final {
        case .finished:
            self = .finished
        case .failed:
            self = .failed
        case .cancelled, .running:
            self = .cancelled
        }
    }
}

extension AgentsTelemetry.FailureKind {
    /// Gives the kind of a failure.
    ///
    /// ``AgentRunFailure/hitMaxTurns(partial:)`` gives ``hitMaxTurns``.
    /// ``AgentRunFailure/mailDeliveryPaused(_:)`` gives ``stopped``: the
    /// Router stopped the delivery of the final messages, thus the run
    /// stopped before it could finish. A failure of the setup, before the run
    /// made its session, gives ``setupFailed``. Each other failure gives
    /// ``error``.
    ///
    /// - Parameter failure: The failure of a run.
    internal init(_ failure: AgentRunFailure) {
        switch failure {
        case .hitMaxTurns:
            self = .hitMaxTurns
        case .mailDeliveryPaused:
            self = .stopped
        case .bodyRenderFailed, .skillRenderFailed, .agentsMdUnreadable, .toolsFailed:
            self = .setupFailed
        case .contextOverflow, .modelFailed:
            self = .error
        }
    }
}

extension AgentRun {
    /// Runs `body` in the span of the run (`FoundationModelsAgents.run`), and
    /// writes the log records of the run: one "enter" record, one start
    /// record before `body` starts, and one end record at the final state
    /// (items A, B and 8 of the OpenTelemetry design of 2026-09-28).
    ///
    /// The span is a child of the `ServiceContext` of the task that calls
    /// this method: the tool span of the `start agent` call for a child run,
    /// or the context of the host for a host-started run. The span has the
    /// ids, the name and the depth of the run when it starts, and the outcome
    /// when `body` gives the final state. It ends when this method returns.
    ///
    /// `TracedCall` writes the "enter" record, and this method writes the
    /// start record and the end record (``logStart(to:)``,
    /// ``logEnd(in:after:to:)``). All three go through one logger that this
    /// method gets from the environment when the run starts
    /// (``AgentEnvironment/makeRunLogger()``).
    ///
    /// - Parameters:
    ///   - environment: The environment of the run. It gives the tracer of
    ///     the span and the logger of the records.
    ///   - body: Gives the final state of the run. It gets the context of the
    ///     span, to open the Router spans of the session as its children.
    /// - Returns: The final state that `body` gave.
    internal func traced(
        in environment: AgentEnvironment,
        _ body: (ServiceContext) async -> AgentRunState
    ) async -> AgentRunState {
        let logger = environment.makeRunLogger()
        // The body throws nothing, thus `try?` discards no error, and the
        // value is always there. `state` is only the static fallback.
        let final = try? await TracedCall.run(
            AgentsTelemetry.SpanName.run,
            ofKind: .internal,
            tracer: environment.tracer,
            logger: logger,
            attributes: { attributes in self.setIdentity(on: &attributes) },
            metadata: identityMetadata,
            { span in
                let started = ContinuousClock.now
                logStart(to: logger)
                let final = await body(span.context)
                Self.record(final, on: span)
                logEnd(in: final, after: ContinuousClock.now - started, to: logger)
                return final
            })
        return final ?? state
    }

    /// The log metadata of each record of the run: the same ids, name and
    /// depth as the span attributes. No value is content.
    internal var identityMetadata: Logger.Metadata {
        var metadata: Logger.Metadata = [
            AgentsTelemetry.LogMetadataKey.agentName: .string(agent.id),
            AgentsTelemetry.LogMetadataKey.runID: .string(id.description),
            AgentsTelemetry.LogMetadataKey.depth: .string("\(depth)")
        ]
        metadata[AgentsTelemetry.LogMetadataKey.parentRunID] = parentRunID.map { .string($0.description) }
        metadata[AgentsTelemetry.LogMetadataKey.callerSessionID] = caller.map { .string($0.description) }
        return metadata
    }

    /// Writes the ids, the name and the depth of the run into the attributes
    /// of its span. No value is content.
    ///
    /// - Parameter attributes: The attributes of the span.
    private func setIdentity(on attributes: inout SpanAttributes) {
        attributes[AgentsTelemetry.AttributeKey.agentName] = agent.id
        attributes[AgentsTelemetry.AttributeKey.runID] = id.description
        attributes[AgentsTelemetry.AttributeKey.parentRunID] = parentRunID?.description
        attributes[AgentsTelemetry.AttributeKey.callerSessionID] = caller?.description
        attributes[AgentsTelemetry.AttributeKey.depth] = depth
    }

    /// Writes the outcome of the final state onto the span of the run. A
    /// failed run also gets its failure kind, an ``AgentRunSpanFailure`` as
    /// its error, and the error status. The text of the failure never goes
    /// onto the span.
    ///
    /// - Parameters:
    ///   - final: The final state of the run.
    ///   - span: The span of the run.
    private static func record(_ final: AgentRunState, on span: any Span) {
        span.attributes[AgentsTelemetry.AttributeKey.outcome] = AgentsTelemetry.Outcome(final).rawValue
        guard case .failed(let failure) = final else {
            return
        }
        let kind = AgentsTelemetry.FailureKind(failure)
        span.attributes[AgentsTelemetry.AttributeKey.failureKind] = kind.rawValue
        span.recordError(AgentRunSpanFailure(kind: kind))
        span.setStatus(SpanStatus(code: .error))
    }
}
