/// The telemetry vocabulary of the package: the name of the span of a run,
/// the key of each span attribute and each log metadata value, the label of
/// the logger, the name of each metric, and the values of the outcome of a
/// run.
///
/// Rule 3 of the OpenTelemetry design of 2026-09-28: each package keeps all of
/// its telemetry names in one vocabulary file. A name is written one time,
/// here, and each other source file reads it from here. A name is part of the
/// observable surface of the package: a dashboard, a query or an alert of a
/// host reads it. Thus change a name only as a deliberate break.
///
/// Each name starts with the prefix `FoundationModelsAgents.`, thus a span, a
/// log record or a metric of this package stays recognizable beside the
/// telemetry of the Router, of Extras and of the host.
///
/// The package uses only the APIs `swift-distributed-tracing`, `swift-log` and
/// `swift-metrics`. It bootstraps no backend: the executable of the host does.
/// Until the host bootstraps a backend, each span, log record and metric goes
/// to the no-op default of its API. Make a logger or a metric for each run,
/// never in a stored `static let`: a logger keeps the handler of the time
/// that it was made, and a metric keeps the factory of that time.
///
/// ## No content
///
/// A span attribute, a log message, a log metadata value and a metric
/// dimension never carry content: no prompt text, no task text, no response
/// text, no final message text, no tool arguments and no tool output. Each
/// record leaves the process through the backend of the host, and the package
/// cannot know where that backend sends it. Names, ids, counts, depths,
/// outcomes and durations are safe. Content is not.
///
/// `TelemetryContentSafetyTests` proves the rule: it runs a scripted parent
/// and child with a secret word in the task text, in the answer of the child
/// and in a tool argument, and it fails when a span, a log record or a metric
/// holds the secret word.
enum AgentsTelemetry {
    /// The prefix of each name of the package.
    private static let prefix = "FoundationModelsAgents."

    /// The label of each logger of the package: the logger of the runner and
    /// of its runs. A label is a name, not content.
    static let logLabel = prefix + "runner"

    /// The operation name of each span of the package.
    enum SpanName {
        /// The span of one agent run, from its start to its final state. The
        /// name carries no content.
        static let run = prefix + "run"
    }

    /// The key of each attribute of the span of a run.
    ///
    /// A key names an identifier, a name, a count or an outcome. The value of
    /// a key never holds content.
    enum AttributeKey {
        /// The name of the agent of the run: the id of its definition. The
        /// value is a name, not content.
        static let agentName = prefix + "agent.name"

        /// The id of the run. The value is an id, not content.
        static let runID = prefix + "run.id"

        /// The id of the run that started this run. A run that the host
        /// started has no parent run, and its span has no such key. The value
        /// is an id, not content.
        static let parentRunID = prefix + "run.parent_id"

        /// The id of the session whose tool call started the run. A run that
        /// the host started has no caller session, and its span has no such
        /// key. The value is an id, not content.
        static let callerSessionID = prefix + "caller.session_id"

        /// The depth of the run: a host-started run is at
        /// `AgentRunner.hostDepth`, and each child run is one level deeper.
        /// The value is a count, not content.
        static let depth = prefix + "run.depth"

        /// How the run ended. See ``AgentsTelemetry/Outcome``. The value is an
        /// outcome, not content.
        static let outcome = prefix + "run.outcome"

        /// Why a failed run failed. See ``AgentsTelemetry/FailureKind``. Only
        /// a run whose ``outcome`` is ``AgentsTelemetry/Outcome/failed`` has
        /// this key. The value is a kind, not the text of the failure, thus
        /// it carries no content.
        static let failureKind = prefix + "run.failure_kind"
    }

    /// The key of each metadata value of the log records of a run.
    ///
    /// Each key is the key of the span attribute with the same meaning, thus
    /// a log record and a span of one run use the same keys.
    enum LogMetadataKey {
        /// The name of the agent of the run. The value is a name, not
        /// content.
        static let agentName = AttributeKey.agentName

        /// The id of the run. The value is an id, not content.
        static let runID = AttributeKey.runID

        /// The id of the run that started this run. The value is an id, not
        /// content.
        static let parentRunID = AttributeKey.parentRunID

        /// The id of the session whose tool call started the run. The value is
        /// an id, not content.
        static let callerSessionID = AttributeKey.callerSessionID

        /// The depth of the run. The value is a count, not content.
        static let depth = AttributeKey.depth

        /// How the run ended. The value is an outcome, not content.
        static let outcome = AttributeKey.outcome

        /// Why a failed run failed. The value is a kind, not content.
        static let failureKind = AttributeKey.failureKind
    }

    /// The name of each metric of the package.
    ///
    /// A dimension of a metric has a small, fixed set of values: the agent
    /// name and the outcome. A run id, a session id or any other value with no
    /// limit is never a dimension.
    enum MetricName {
        /// The counter of the agent runs that ended. The name carries no
        /// content.
        static let runCount = prefix + "runs"

        /// The timer of the duration of each agent run, from its start to its
        /// final state. The name carries no content.
        static let runDuration = prefix + "run.duration"
    }

    /// The value that ``AttributeKey/outcome`` carries: how a run ended.
    ///
    /// Each value is one of the three terminal states of a run. A value is an
    /// outcome, not content.
    enum Outcome: String {
        /// The run finished with a result.
        case finished

        /// The run failed. ``AttributeKey/failureKind`` tells why.
        case failed

        /// The run was cancelled before it finished.
        case cancelled
    }

    /// The value that ``AttributeKey/failureKind`` carries: why a run failed.
    ///
    /// The set of values is fixed, thus a kind can also be a metric
    /// dimension. A kind is not the text of the failure, thus it carries no
    /// content.
    enum FailureKind: String {
        /// The run went above the `maxTurns` limit of its agent.
        case hitMaxTurns

        /// The run failed with an error.
        case error

        /// The run was stopped.
        case stopped
    }
}
