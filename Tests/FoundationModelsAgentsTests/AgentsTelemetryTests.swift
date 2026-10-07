@testable import FoundationModelsAgents
import Testing

/// Pins the telemetry vocabulary of the package (rule 3 of the OpenTelemetry
/// design of 2026-09-28): `AgentsTelemetry` holds each name that the package
/// emits, and each name starts with the module prefix.
///
/// A name is part of the observable surface. A dashboard, a query or an alert
/// of a host reads it, thus this suite states each name and each value.
@Suite("AgentsTelemetry vocabulary")
struct AgentsTelemetryTests {
    /// The prefix of each name of the package.
    private static let prefix = "FoundationModelsAgents."

    /// The span attribute keys, in the order of the card.
    private static let attributeKeys = [
        AgentsTelemetry.AttributeKey.agentName,
        AgentsTelemetry.AttributeKey.runID,
        AgentsTelemetry.AttributeKey.parentRunID,
        AgentsTelemetry.AttributeKey.callerSessionID,
        AgentsTelemetry.AttributeKey.depth,
        AgentsTelemetry.AttributeKey.outcome,
        AgentsTelemetry.AttributeKey.failureKind,
        AgentsTelemetry.AttributeKey.messageDirection,
        AgentsTelemetry.AttributeKey.messageOutcome,
        AgentsTelemetry.AttributeKey.messageLength
    ]

    /// The log metadata keys, in the same order as ``attributeKeys``.
    private static let logMetadataKeys = [
        AgentsTelemetry.LogMetadataKey.agentName,
        AgentsTelemetry.LogMetadataKey.runID,
        AgentsTelemetry.LogMetadataKey.parentRunID,
        AgentsTelemetry.LogMetadataKey.callerSessionID,
        AgentsTelemetry.LogMetadataKey.depth,
        AgentsTelemetry.LogMetadataKey.outcome,
        AgentsTelemetry.LogMetadataKey.failureKind,
        AgentsTelemetry.LogMetadataKey.messageDirection,
        AgentsTelemetry.LogMetadataKey.messageOutcome,
        AgentsTelemetry.LogMetadataKey.messageLength
    ]

    /// The log metadata keys that no span attribute has: the keys of the end
    /// record of a run.
    private static let logOnlyKeys = [
        AgentsTelemetry.LogMetadataKey.durationSeconds,
        AgentsTelemetry.LogMetadataKey.errorType
    ]

    /// The metric names.
    private static let metricNames = [
        AgentsTelemetry.MetricName.runCount,
        AgentsTelemetry.MetricName.runDuration
    ]

    /// The message of each start and end record of a run.
    private static let logMessages = [
        AgentsTelemetry.LogMessage.runStarted,
        AgentsTelemetry.LogMessage.runEnded(.finished),
        AgentsTelemetry.LogMessage.runEnded(.failed),
        AgentsTelemetry.LogMessage.runEnded(.cancelled)
    ]

    /// Each distinct name of the vocabulary. The log metadata keys of
    /// ``logMetadataKeys`` are the attribute keys, and the message of a
    /// message record is the name of its span event, thus the list holds
    /// each of them one time.
    private static let names =
        [AgentsTelemetry.SpanName.run, AgentsTelemetry.EventName.messageSent, AgentsTelemetry.logLabel]
            + attributeKeys + logOnlyKeys + metricNames + logMessages

    @Test("each name starts with the module prefix")
    func eachNameStartsWithTheModulePrefix() {
        #expect(Self.names.filter { !$0.hasPrefix(Self.prefix) } == [])
    }

    @Test("no two names are the same")
    func noTwoNamesAreTheSame() {
        #expect(Set(Self.names).count == Self.names.count)
    }

    @Test("the span of a run is FoundationModelsAgents.run")
    func theSpanOfARunHasItsName() {
        #expect(AgentsTelemetry.SpanName.run == "FoundationModelsAgents.run")
    }

    @Test("the log metadata keys are the span attribute keys")
    func theLogMetadataKeysAreTheAttributeKeys() {
        #expect(Self.logMetadataKeys == Self.attributeKeys)
    }

    @Test("the metric dimension keys are the span attribute keys of the agent name, the outcome and the failure kind")
    func theMetricDimensionsAreAttributeKeys() {
        let dimensions = [
            AgentsTelemetry.MetricDimension.agentName,
            AgentsTelemetry.MetricDimension.outcome,
            AgentsTelemetry.MetricDimension.failureKind
        ]

        #expect(
            dimensions == [
                AgentsTelemetry.AttributeKey.agentName,
                AgentsTelemetry.AttributeKey.outcome,
                AgentsTelemetry.AttributeKey.failureKind
            ])
    }

    @Test("the outcome values are finished, failed and cancelled")
    func theOutcomeValuesAreTheThreeEnds() {
        let values = [AgentsTelemetry.Outcome.finished, .failed, .cancelled].map(\.rawValue)

        #expect(values == ["finished", "failed", "cancelled"])
    }

    @Test("the failure kinds are hitMaxTurns, error, stopped, setupFailed and catalogNotLoaded")
    func theFailureKindsAreTheFiveKinds() {
        let values = [
            AgentsTelemetry.FailureKind.hitMaxTurns, .error, .stopped, .setupFailed, .catalogNotLoaded
        ].map(\.rawValue)

        #expect(values == ["hitMaxTurns", "error", "stopped", "setupFailed", "catalogNotLoaded"])
    }

    @Test("the messages of the start and end records name the span of a run and the outcome")
    func theLogMessagesNameTheSpanAndTheOutcome() {
        #expect(
            Self.logMessages == [
                "FoundationModelsAgents.run started", "FoundationModelsAgents.run finished",
                "FoundationModelsAgents.run failed", "FoundationModelsAgents.run cancelled"
            ])
    }

    @Test("the event and the record of a message are FoundationModelsAgents.agent.message.sent")
    func theMessageEventAndRecordHaveTheirName() {
        #expect(AgentsTelemetry.EventName.messageSent == "FoundationModelsAgents.agent.message.sent")
        #expect(AgentsTelemetry.LogMessage.messageSent == AgentsTelemetry.EventName.messageSent)
    }

    @Test("the message directions are to_run and to_caller, and the message outcomes are delivered, ended and no_caller")
    func theMessageValuesAreFixed() {
        let directions = [AgentsTelemetry.MessageDirection.toRun, .toCaller].map(\.rawValue)
        let outcomes = [AgentsTelemetry.MessageOutcome.delivered, .ended, .noCaller].map(\.rawValue)

        #expect(directions == ["to_run", "to_caller"])
        #expect(outcomes == ["delivered", "ended", "no_caller"])
    }
}
