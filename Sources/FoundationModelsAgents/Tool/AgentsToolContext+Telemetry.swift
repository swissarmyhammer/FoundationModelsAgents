import FoundationModelsRouter
import Logging
import Tracing

/// What the telemetry tells of one call of `send agent` or `send caller`:
/// the direction, the run, the outcome and the length of the message.
///
/// The record never holds the text of the message. The text is content, and
/// a log record or a span event leaves the process through the backend of the
/// host (``AgentsTelemetry``, "No content").
struct AgentMessageRecord {
    /// Where the message went.
    let direction: AgentsTelemetry.MessageDirection

    /// The run that got the message (`send agent`), or the run that sent it
    /// (`send caller`). `nil` when the caller of `send caller` is not a run.
    let run: AgentRun?

    /// What became of the message.
    let outcome: AgentsTelemetry.MessageOutcome

    /// The count of characters of the message.
    let length: Int

    /// The log metadata of the record: the direction, the outcome, the
    /// length, and the name and the id of ``run`` when there is a run.
    var metadata: Logger.Metadata {
        var metadata: Logger.Metadata = [
            AgentsTelemetry.LogMetadataKey.messageDirection: .string(direction.rawValue),
            AgentsTelemetry.LogMetadataKey.messageOutcome: .string(outcome.rawValue),
            AgentsTelemetry.LogMetadataKey.messageLength: .string("\(length)")
        ]
        metadata[AgentsTelemetry.LogMetadataKey.agentName] = run.map { .string($0.agent.id) }
        metadata[AgentsTelemetry.LogMetadataKey.runID] = run.map { .string($0.id.description) }
        return metadata
    }

    /// The attributes of the span event: the same keys and values as
    /// ``metadata``. The length is a count.
    var attributes: SpanAttributes {
        var attributes: SpanAttributes = [:]
        attributes[AgentsTelemetry.AttributeKey.messageDirection] = direction.rawValue
        attributes[AgentsTelemetry.AttributeKey.messageOutcome] = outcome.rawValue
        attributes[AgentsTelemetry.AttributeKey.messageLength] = length
        attributes[AgentsTelemetry.AttributeKey.agentName] = run?.agent.id
        attributes[AgentsTelemetry.AttributeKey.runID] = run?.id.description
        return attributes
    }
}

extension AgentsTelemetry.MessageOutcome {
    /// Gives the outcome of a message that ``AgentRun/deliver(_:)`` took or
    /// refused.
    ///
    /// - Parameter outcome: What the run did with the message.
    init(_ outcome: AgentRunMessageOutcome) {
        switch outcome {
        case .delivered:
            self = .delivered
        case .ended:
            self = .ended
        }
    }
}

extension AgentsToolContext {
    /// Writes one `agent.message.sent` log record, and adds one
    /// `agent.message.sent` event to the active span of the call.
    ///
    /// The logger is the logger of the runs (``AgentEnvironment/makeRunLogger()``).
    /// The active span is the span of `ServiceContext.current` in the tracer
    /// of the environment, or in `InstrumentationSystem.tracer` when the
    /// environment has no tracer. In a Router session it is the tool span of
    /// the call. A call outside a span, for example a command of
    /// ``AgentsCLI``, writes only the log record.
    ///
    /// - Parameter message: The record of the message.
    func record(_ message: AgentMessageRecord) {
        let environment = runner.environment
        environment.makeRunLogger().info("\(AgentsTelemetry.LogMessage.messageSent)", metadata: message.metadata)
        guard let context = ServiceContext.current else {
            return
        }
        let tracer = environment.tracer ?? InstrumentationSystem.tracer
        tracer.activeSpan(identifiedBy: context)?.addEvent(
            SpanEvent(name: AgentsTelemetry.EventName.messageSent, attributes: message.attributes))
    }

    /// Records one message of `send caller` from the run of this call.
    ///
    /// The session of a run has the id of the run, thus the session of the
    /// call gives the run that sent the message. A session that is not a run
    /// gives no run.
    ///
    /// - Parameters:
    ///   - message: The text of the message. Only its length goes to the
    ///     record.
    ///   - outcome: What became of the message.
    func recordMessageToCaller(_ message: String, outcome: AgentsTelemetry.MessageOutcome) async {
        let sender = await runOfCall()
        record(AgentMessageRecord(direction: .toCaller, run: sender, outcome: outcome, length: message.count))
    }

    /// Gives the run whose session made this call.
    ///
    /// - Returns: The run with the id of the session of
    ///   `ToolContext.current`, or `nil` outside a Router session and for a
    ///   session that is not a run.
    private func runOfCall() async -> AgentRun? {
        guard let sessionID = ToolContext.current?.sessionID else {
            return nil
        }
        return await runner.run(id: sessionID)
    }
}
