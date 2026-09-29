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
        AgentsTelemetry.AttributeKey.failureKind
    ]

    /// The log metadata keys, in the same order as ``attributeKeys``.
    private static let logMetadataKeys = [
        AgentsTelemetry.LogMetadataKey.agentName,
        AgentsTelemetry.LogMetadataKey.runID,
        AgentsTelemetry.LogMetadataKey.parentRunID,
        AgentsTelemetry.LogMetadataKey.callerSessionID,
        AgentsTelemetry.LogMetadataKey.depth,
        AgentsTelemetry.LogMetadataKey.outcome,
        AgentsTelemetry.LogMetadataKey.failureKind
    ]

    /// The metric names.
    private static let metricNames = [
        AgentsTelemetry.MetricName.runCount,
        AgentsTelemetry.MetricName.runDuration
    ]

    /// Each distinct name of the vocabulary. The log metadata keys are the
    /// attribute keys, thus the list holds them one time.
    private static let names =
        [AgentsTelemetry.SpanName.run, AgentsTelemetry.logLabel] + attributeKeys + metricNames

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

    @Test("the outcome values are finished, failed and cancelled")
    func theOutcomeValuesAreTheThreeEnds() {
        let values = [AgentsTelemetry.Outcome.finished, .failed, .cancelled].map(\.rawValue)

        #expect(values == ["finished", "failed", "cancelled"])
    }

    @Test("the failure kinds are hitMaxTurns, error and stopped")
    func theFailureKindsAreTheThreeKinds() {
        let values = [AgentsTelemetry.FailureKind.hitMaxTurns, .error, .stopped].map(\.rawValue)

        #expect(values == ["hitMaxTurns", "error", "stopped"])
    }
}
