import Foundation
import FoundationModels
import FoundationModelsExtras
import FoundationModelsRouter
import FoundationModelsSkills
import Logging
import Metrics
import Tracing
import ULID

/// The dependencies and the limits of the agent runs of one host.
///
/// The host makes the dependencies. The profile and the skills registry
/// have no default: the host session and the sub-agents use the same
/// instances.
///
/// The skills registry is the one source of the skills. The environment
/// makes the `skills` tool from it, and puts that tool in its tool catalog
/// under the name `skills`. The `skills:` preload of each run reads the same
/// registry, with the same visibility rule. The host gives its root session
/// ``skillsTool``, thus the host and the runs see the same skills.
///
/// ```swift
/// let env = try await AgentEnvironment.make(profile: profile, skills: skills,
///                                           workingDirectory: projectURL, tools: tools,
///                                           defaultSlot: .standard, maxConcurrentAgents: 4, maxDepth: 3)
/// let root = profile.standard.makeSession(
///     configuration: SessionConfiguration(
///         instructions: instructions, tools: [env.skillsTool, agentsTool], userPresence: .headless))
/// ```
public struct AgentEnvironment: Sendable {
    /// Tells if the `skills` tool shows a skill. The `skills:` preload uses
    /// the same rule.
    public typealias SkillsVisibility = @Sendable (SkillMetadata) -> Bool

    /// Makes the token budget of a run from the resolved context of its
    /// model, in tokens. `nil` gives a run with no budget.
    public typealias BudgetFactory = @Sendable (Int) -> TokenBudget?

    /// Receives each session output of one agent run, with that run. The
    /// output holds the event and its origin, thus a host can follow the id
    /// chain from the mail to the event. ``runEventObserver`` tells the
    /// contract.
    public typealias RunEventObserver = @Sendable (AgentRun, SessionOutput) -> Void

    /// Sends a message to a caller session that the runner does not hold as a
    /// run, for example the root session of a host. It gets the text, the id
    /// of the session that sends the message, and the id of the caller
    /// session. It returns the id of the mail that it posted to the caller, or `nil` when the
    /// caller got no mail. A host closure that returned `Bool` must now return the `MailID`: this
    /// is a source break by design, because the host joins the id to its projection of the message.
    public typealias CallerMail = @Sendable (_ message: String, _ sender: ULID, _ caller: ULID) async -> MailID?

    /// Marks the session of a run as ended, with the reason. A host gives
    /// `{ try await directory.markEnded($0, reason: $1) }` over its
    /// `RouterSessionDirectory`. The run calls it when it reaches a real end,
    /// before it gives its result. It never calls it for a stop of the
    /// runner, thus a later start of the host can restore the run.
    public typealias SessionEnding = @Sendable (_ session: ULID, _ reason: SessionEndReason) async throws -> Void

    /// Completes a claimed call on a caller session that the runner does not hold as a run, for
    /// example the root session of the host. It gets the caller session, the key of the call,
    /// the outcome, and the text of the result. It returns `true` when the call was an open
    /// claim and the closure completed it. A host gives
    /// `{ try await session.completeClaimedRun(key, outcome: outcome, detail: detail) }` over
    /// the live session.
    public typealias ClaimCompletion = @Sendable (
        _ caller: ULID, _ key: RunKey, _ outcome: OperationOutcome, _ detail: String?
    ) async -> Bool

    /// The default of ``maxConcurrentAgents``.
    public static let defaultMaxConcurrentAgents = 4

    /// The default of ``maxDepth``.
    public static let defaultMaxDepth = 3

    /// The default of ``maxRetainedRuns``.
    public static let defaultMaxRetainedRuns = 100

    /// The default of ``budget``: `TokenBudget(limit:)` with the resolved
    /// context of the model.
    public static let defaultBudget: BudgetFactory = { TokenBudget(limit: $0) }

    /// The default visibility rule of the `skills` tool: it shows each skill
    /// that the model can see (`SkillMetadata.isModelVisible`).
    public static let defaultSkillsVisibility: SkillsVisibility = { $0.isModelVisible }

    /// The resolved profile. Each run makes its session on
    /// `profile.standard` or `profile.flash`.
    public let profile: LanguageModelProfile

    /// The skills registry of the host. The `skills` tool and the `skills:`
    /// key of an agent read it.
    public let skills: SkillsRegistry

    /// The `skills` tool, made from ``skills``.
    ///
    /// ``tools`` holds this tool under its name, `skills`, thus each run gets
    /// it. Give it to the root session of the host too: then the host and the
    /// runs read one registry.
    public let skillsTool: SkillsCatalogTool

    /// The visibility rule of ``skillsTool``. The `skills:` preload skips each
    /// skill that this rule hides.
    let skillsVisibility: SkillsVisibility

    /// The model that chooses among the candidates of a `search skill` call
    /// of ``skillsTool`` and of a `find agents` call of the `agents` tool, or
    /// `nil` for the retrieval rank with no model.
    let selectionModel: (any FoundationModels.LanguageModel)?

    /// The working directory of each run that has no other folder: no folder
    /// of the start request, and no parent run. A run that a host session
    /// starts, and the session is not a run, and a host-driven run with no
    /// folder (``AgentRunner/start(_:prompt:workingDirectory:)``), work in
    /// it. An agent of the agent folder form also works in it, not in its
    /// own folder.
    public let workingDirectory: URL

    /// The tools that the `tools` and `disallowedTools` keys select from: the
    /// tools of the host, and ``skillsTool`` under the name `skills`.
    public let tools: ToolCatalog

    /// The slot of a host-started run when its `model` is absent or
    /// `inherit`. It is `.standard` or `.flash`.
    public let defaultSlot: ModelSlot

    /// The count of runs that can have a turn in operation at one time. It
    /// is one or more.
    public let maxConcurrentAgents: Int

    /// The depth limit. A host-started run has depth one, and a child has
    /// the depth of its parent plus one. It is one or more.
    public let maxDepth: Int

    /// The count of finished run records that the runner keeps for
    /// `check agent`. The runner removes the oldest record first. It is
    /// zero or more.
    public let maxRetainedRuns: Int

    /// Makes the token budget of each run from the resolved context of its
    /// model.
    public let budget: BudgetFactory

    /// The tracer of the span of each run, or `nil` to read
    /// `InstrumentationSystem.tracer` when the run starts.
    ///
    /// `nil` is the default. A host that bootstraps a tracing backend after
    /// it makes the environment still gets the spans, because the run reads
    /// the tracer only when it starts. A child run starts in the body of a
    /// `start agent` call, under the detached pump of the Router, thus a
    /// task-local tracer of `withTracer` does not reach it. Give the tracer
    /// here, and to `Router(tracer:)`, to send each span to one tracer that
    /// is not the bootstrapped one.
    public let tracer: (any Tracer)?

    /// The logger of the log records of each run, or `nil` to make a new
    /// `Logger` with the label of the package when each run starts.
    ///
    /// `nil` is the default. The package never bootstraps the logging
    /// system: a new logger uses the backend that the host bootstrapped. A
    /// child run starts in the body of a `start agent` call, under the
    /// detached pump of the Router, thus a log handler that the host binds
    /// to its own task does not reach it. Give a logger here to send the
    /// records of each run, the child runs too, to one handler.
    public let logger: Logger?

    /// The metrics factory of the run counter and the run timer, or `nil` to
    /// read `MetricsSystem.factory` when each run ends.
    ///
    /// `nil` is the default. The package never bootstraps the metrics
    /// system: with `nil`, each run uses the factory that the host
    /// bootstrapped, or the task-local factory of `withMetricsFactory`. A
    /// child run starts in the body of a `start agent` call, under the
    /// detached pump of the Router, thus a task-local factory does not reach
    /// it. Give a factory here to send the metrics of each run, the child
    /// runs too, to one factory.
    public let metricsFactory: (any MetricsFactory)?

    /// The settle period of the session of each run, in seconds: how long a
    /// background call of the run, for example `start agent`, waits for its
    /// own work. Never negative.
    ///
    /// Work that ends in this time gives its own output to the call. Work
    /// that continues gives the pending envelope, and its result comes later
    /// as mail. `0` gives the pending envelope at once. The session of each
    /// run gets this value as `SessionConfiguration.inlineSettleGrace`.
    public let inlineSettleGrace: TimeInterval

    /// The observer of the session events of each run, or `nil` for no
    /// observer. `nil` is the default.
    ///
    /// The observer gets each `SessionOutput`: the event and its origin.
    /// Each run calls the observer, the child runs too. The run reads the
    /// session-event subscription of its session in one loop, and calls the
    /// observer synchronously in that loop, first for each event, before the
    /// run uses the event. Thus the observer gets the events of one run in
    /// the order of that subscription. The observer holds the loop of the
    /// run while it runs: it must return quickly, and it must not wait for
    /// the run. Two runs can call it at the same time.
    ///
    /// The open `SessionEvent.toolInvocation(_:toolCallID:)` record of a
    /// tool run carries the completion token of that tool run. The Router
    /// gives the open record to the subscription before the body of the
    /// tool starts. The loop of the run and the body of the tool are two
    /// tasks, thus the observer gets the open record while the body runs
    /// at the latest, and normally before the body gives output. The
    /// package does not promise that the observer runs before the first
    /// output of the body.
    public let runEventObserver: RunEventObserver?

    /// Sends a message of a restored run to its caller, when the caller is a
    /// session that the runner does not hold as a run, or `nil` for no such
    /// route. The route is the mail route of a caller link: a restored run has
    /// no live `start agent` call of its caller. A caller that is a run of the
    /// runner gets the message without this closure.
    public let callerMail: CallerMail?

    /// The text at the start of the instructions of each run, or `nil` for
    /// no such text. `nil` is the default.
    ///
    /// The instructions of a run are, in this order: this text, the
    /// `AGENTS.md` text of the working folder of the run, the rendered body,
    /// then the rendered body of each skill of the `skills:` key. A new run
    /// and a restored run both start with this text. A child run gets it
    /// too. A text that holds only whitespace adds nothing.
    ///
    /// The instructions of a main session do not hold this text
    /// (``AgentRunner/sessionAgentInstructions(for:)`` and
    /// ``AgentRunner/defaultAgentInstructions()``). The host adds the text to
    /// its main session itself, thus the text occurs one time.
    public let instructionsPreamble: String?

    /// Gives the template context of the body of one run, from the
    /// definition of the run and the names of its resolved tools.
    ///
    /// A host gives the values of the tool selection of the run, for example
    /// `tools.shell.enabled`, thus a body that reads them sees the tools that
    /// the model of the run has.
    public typealias RunTemplateContext =
        @Sendable (_ definition: AgentDefinition, _ toolNames: [String]) -> [String: TemplateValue]

    /// The template context of the body of each run, or `nil` (the default)
    /// for the template context of the registry.
    ///
    /// The run resolves its tools first. Then it calls this closure with its
    /// definition and the names of its resolved tools. Its body and each
    /// partial of the body render with the result in place of the template
    /// context of the agent registry. Each skill of its `skills:` preload, and
    /// each render of its `skills` tool, use the result in place of the
    /// values of the skills registry: the run gets its own `skills` tool,
    /// which shares the index of ``skillsTool``. A new run and a restored run
    /// both get the values. The `agents` group stays off for an agent that
    /// denies the `agents` tool. A main session does not use this closure.
    public let runTemplateContext: RunTemplateContext?

    /// The host closure that marks the session of a run as ended, or `nil`
    /// for none (``SessionEnding``).
    public internal(set) var sessionEnding: SessionEnding? = nil

    /// The host closure that completes a claimed call on a caller that is not a run, or `nil`
    /// for none (``ClaimCompletion``).
    public internal(set) var claimCompletion: ClaimCompletion? = nil

    /// The recording root of the sessions of the runs, or `nil` for the default of the Router.
    /// A host sets the root of its own sessions, thus one `RouterSessionDirectory` finds the
    /// root session and its runs, and a restart can restore the runs.
    public internal(set) var recordingRoot: URL? = nil

    /// Gives a copy of the environment whose runs record their sessions under `recordingRoot`.
    ///
    /// - Parameter recordingRoot: The root, or `nil` for the default of the Router.
    /// - Returns: The copy.
    public func withRecordingRoot(_ recordingRoot: URL?) -> AgentEnvironment {
        var copy = self
        copy.recordingRoot = recordingRoot
        return copy
    }

    /// The reader of the recorded events of a session, or `nil` for none. A restored child session
    /// gets it, because a cold resume has no live parent call that could give it. A tool of that
    /// session reads through `ToolContext.transcript(of:)`. With `nil`, that call throws
    /// `SessionTranscriptError.noSource`.
    public internal(set) var transcriptReader: (any SessionTranscriptReader)? = nil

    /// Gives a copy of the environment whose restored child sessions get `transcriptReader`.
    ///
    /// - Parameter transcriptReader: The reader, or `nil` for none.
    /// - Returns: The copy.
    public func withTranscriptReader(_ transcriptReader: (any SessionTranscriptReader)?) -> AgentEnvironment {
        var copy = self
        copy.transcriptReader = transcriptReader
        return copy
    }

    /// Gives a copy of the environment with a host closure that marks the
    /// session of a run as ended (``SessionEnding``).
    ///
    /// - Parameter sessionEnding: The closure, or `nil` for none.
    /// - Returns: The copy.
    public func withSessionEnding(_ sessionEnding: SessionEnding?) -> AgentEnvironment {
        var copy = self
        copy.sessionEnding = sessionEnding
        return copy
    }

    /// Gives a copy of the environment with a host closure that completes a claimed call on a
    /// caller session that is not a run (``ClaimCompletion``).
    ///
    /// - Parameter claimCompletion: The closure, or `nil` for none.
    /// - Returns: The copy.
    public func withClaimCompletion(_ claimCompletion: ClaimCompletion?) -> AgentEnvironment {
        var copy = self
        copy.claimCompletion = claimCompletion
        return copy
    }

    /// The most answers in a row that mail alone starts in the session of a
    /// run, with no caller message between them. Message mail and final
    /// messages both count. When the Router holds the mail at this limit,
    /// the run pauses: it waits until each run that it started ended, then it
    /// fails with ``AgentRunFailure/mailDeliveryPaused(_:)`` and the held
    /// results (``AgentRun/pause``). The limit is a guard against a chain of
    /// mail with no end, thus the run does not end the hold itself.
    ///
    /// The default is the default of the Router,
    /// `SessionConfiguration.defaultMailOnlyAnswerLimit`.
    var mailOnlyAnswerLimit = SessionConfiguration.defaultMailOnlyAnswerLimit

    /// The user presence of the session of each run that has no question
    /// target, for example a host-started run. It is `.headless`: nothing can
    /// answer a question of that run session, thus a question of the run
    /// ends at once with a cancel that gives `RunPlane.noUserPresentReason`,
    /// and the run goes on. A run that a `start agent` call started takes the
    /// user presence of the session of that call, and sends its questions to
    /// that session (``AgentRunRequest/questionTarget``).
    ///
    /// Only tests change this value: an interactive run session lets a test
    /// reach the question guard of the run (``AgentRun/answerQuestion(of:on:)``).
    var runUserPresence = UserPresence.headless

    /// Makes an environment, and makes its `skills` tool from `skills`.
    ///
    /// The function is `async throws` because `SkillsTool.make` reads the
    /// registry and builds the search index of the tool.
    ///
    /// A value out of its range is a programmer error and stops the process.
    /// A `skills` entry in `tools` is a programmer error too: the environment
    /// adds the `skills` tool itself, thus the runs and the preload cannot
    /// read two registries.
    ///
    /// - Parameters:
    ///   - profile: The resolved profile of the host.
    ///   - skills: The skills registry of the host. The `skills` tool and the
    ///     `skills:` preload read this one registry.
    ///   - skillsSelectionModel: The model that chooses among the candidate
    ///     skills of a `search skill` call (`SkillsTool.make(registry:model:)`),
    ///     or `nil` (the default) for a keyword search with no model
    ///     (`SkillsTool.make(registry:)`). The `find agents` operation of the
    ///     `agents` tool uses the same model to choose among the candidate
    ///     agents.
    ///   - skillsCatalogCharacterLimit: The most characters that the catalog
    ///     list in the description of the `skills` tool can have. The default
    ///     is `SkillsTool.defaultCatalogCharacterLimit`.
    ///   - skillsVisibility: Tells if the `skills` tool shows a skill. The
    ///     `skills:` preload skips each skill that it hides. The default is
    ///     ``defaultSkillsVisibility``.
    ///   - workingDirectory: The working directory of each run that has no
    ///     other folder (``workingDirectory``). The default is the current
    ///     directory of the process.
    ///   - tools: The tool catalog of the host. It must not hold a `skills`
    ///     entry. The default is an empty catalog.
    ///   - defaultSlot: The slot of a host-started run with no `model`. It
    ///     must be `.standard` or `.flash`.
    ///   - maxConcurrentAgents: The count of runs that can have a turn in
    ///     operation at one time. It must be one or more.
    ///   - maxDepth: The depth limit. It must be one or more.
    ///   - maxRetainedRuns: The count of finished run records to keep. It
    ///     must be zero or more.
    ///   - budget: Makes the token budget of each run.
    ///   - tracer: The tracer of the span of each run, or `nil` (the
    ///     default) to read `InstrumentationSystem.tracer` when the run
    ///     starts.
    ///   - logger: The logger of the log records of each run, or `nil` (the
    ///     default) to make a new `Logger` when each run starts.
    ///   - metricsFactory: The metrics factory of the metrics of each run, or
    ///     `nil` (the default) to read `MetricsSystem.factory` when each run
    ///     ends.
    ///   - inlineSettleGrace: The settle period of the session of each run,
    ///     in seconds. The default is `ToolMount.defaultInlineSettleGrace`. A
    ///     negative value acts as `0`.
    ///   - runEventObserver: The observer of the session events of each run,
    ///     or `nil` (the default) for no observer. ``runEventObserver`` tells
    ///     the contract.
    ///   - callerMail: Sends a message of a restored run to a caller session
    ///     that the runner does not hold as a run, or `nil` (the default) for
    ///     no such route. ``callerMail`` tells the contract.
    ///   - instructionsPreamble: The text at the start of the instructions of
    ///     each run, before the `AGENTS.md` text, or `nil` (the default) for
    ///     no such text. ``instructionsPreamble`` tells the contract.
    ///   - runTemplateContext: Gives the template context of the body of
    ///     each run, or `nil` (the default) for the template context of the
    ///     registry. ``runTemplateContext`` tells the contract.
    ///   - sandboxProbe: The probe that tells if the process is sandboxed.
    ///     The environment gives it to `SkillsTool.make`. The default,
    ///     `SandboxProbe.live`, reads the current process. A test gives
    ///     `SandboxProbe.fixed(_:)`.
    /// - Returns: The environment.
    /// - Throws: `ToolModeError.openModeInSandbox` when the mode of `skills`
    ///   is `ToolMode.open` and `sandboxProbe` tells that the process is
    ///   sandboxed. Whatever else `SkillsTool.make` throws.
    public static func make(
        profile: LanguageModelProfile,
        skills: SkillsRegistry,
        skillsSelectionModel: (any FoundationModels.LanguageModel)? = nil,
        skillsCatalogCharacterLimit: Int = SkillsTool.defaultCatalogCharacterLimit,
        skillsVisibility: @escaping SkillsVisibility = defaultSkillsVisibility,
        workingDirectory: URL = URL.currentDirectory(),
        tools: ToolCatalog = ToolCatalog(),
        defaultSlot: ModelSlot = .standard,
        maxConcurrentAgents: Int = defaultMaxConcurrentAgents,
        maxDepth: Int = defaultMaxDepth,
        maxRetainedRuns: Int = defaultMaxRetainedRuns,
        budget: @escaping BudgetFactory = defaultBudget,
        tracer: (any Tracer)? = nil,
        logger: Logger? = nil,
        metricsFactory: (any MetricsFactory)? = nil,
        inlineSettleGrace: TimeInterval = ToolMount.defaultInlineSettleGrace,
        runEventObserver: RunEventObserver? = nil,
        callerMail: CallerMail? = nil,
        instructionsPreamble: String? = nil,
        runTemplateContext: RunTemplateContext? = nil,
        sandboxProbe: SandboxProbe = .live
    ) async throws -> AgentEnvironment {
        let skillsTool = try await makeSkillsTool(
            skills: skills, selectionModel: skillsSelectionModel,
            catalogCharacterLimit: skillsCatalogCharacterLimit, visibility: skillsVisibility,
            sandboxProbe: sandboxProbe)
        return AgentEnvironment(
            profile: profile, skills: skills, skillsTool: skillsTool, skillsVisibility: skillsVisibility,
            selectionModel: skillsSelectionModel, workingDirectory: workingDirectory, tools: tools,
            defaultSlot: defaultSlot, maxConcurrentAgents: maxConcurrentAgents, maxDepth: maxDepth,
            maxRetainedRuns: maxRetainedRuns, budget: budget, tracer: tracer, logger: logger,
            metricsFactory: metricsFactory, inlineSettleGrace: inlineSettleGrace, runEventObserver: runEventObserver,
            callerMail: callerMail, instructionsPreamble: instructionsPreamble,
            runTemplateContext: runTemplateContext)
    }

    /// Makes the `skills` tool from `skills`.
    ///
    /// - Parameters:
    ///   - skills: The skills registry of the host.
    ///   - selectionModel: The model of the selection tier, or `nil` for a
    ///     keyword search with no model.
    ///   - catalogCharacterLimit: The most characters of the catalog list of
    ///     the description.
    ///   - visibility: Tells if the tool shows a skill.
    ///   - sandboxProbe: The probe that tells if the process is sandboxed.
    /// - Returns: The tool.
    /// - Throws: `ToolModeError.openModeInSandbox` when the mode of `skills`
    ///   is `ToolMode.open` and `sandboxProbe` tells that the process is
    ///   sandboxed. Whatever else `SkillsTool.make` throws.
    static func makeSkillsTool(
        skills: SkillsRegistry,
        selectionModel: (any FoundationModels.LanguageModel)?,
        catalogCharacterLimit: Int,
        visibility: @escaping SkillsVisibility,
        sandboxProbe: SandboxProbe
    ) async throws -> SkillsCatalogTool {
        let noEmbedder: (any PooledEmbedding)? = nil
        let followsReloads = true
        let make = skillsToolFactory(selectionModel: selectionModel)
        return try await make(skills, noEmbedder, followsReloads, catalogCharacterLimit, visibility, sandboxProbe)
    }

    /// The shape of the `SkillsTool.make` overload that takes no model.
    /// ``skillsToolFactory(selectionModel:)`` gives a factory of this shape
    /// for each of the two overloads.
    private typealias SkillsToolFactory = (
        _ registry: SkillsRegistry,
        _ embedder: (any PooledEmbedding)?,
        _ followReloads: Bool,
        _ catalogCharacterLimit: Int,
        _ visibilityPredicate: @escaping SkillsVisibility,
        _ sandboxProbe: SandboxProbe
    ) async throws -> SkillsCatalogTool

    /// Gives the `SkillsTool.make` overload that agrees with `selectionModel`.
    ///
    /// FoundationModelsSkills has two `SkillsTool.make` overloads. One takes
    /// a model and has a selection tier. The other takes no model and has
    /// only keyword retrieval. Neither overload takes an optional model, thus
    /// a `nil` model needs the other overload. This function chooses the
    /// overload, and binds the model when there is one. Thus
    /// ``makeSkillsTool(skills:selectionModel:catalogCharacterLimit:visibility:sandboxProbe:)``
    /// gives the shared arguments in one call only.
    ///
    /// - Parameter selectionModel: The model of the selection tier, or `nil`
    ///   for a keyword search with no model.
    /// - Returns: The factory that makes the `skills` tool.
    private static func skillsToolFactory(
        selectionModel: (any FoundationModels.LanguageModel)?
    ) -> SkillsToolFactory {
        guard let selectionModel else {
            return SkillsTool.make(
                registry:embedder:followReloads:catalogCharacterLimit:visibilityPredicate:sandboxProbe:)
        }
        return {
            try await SkillsTool.make(
                registry: $0, model: selectionModel, embedder: $1, followReloads: $2,
                catalogCharacterLimit: $3, visibilityPredicate: $4, sandboxProbe: $5)
        }
    }

    /// Makes an environment over a `skills` tool that is already made.
    ///
    /// ``make(profile:skills:skillsSelectionModel:skillsCatalogCharacterLimit:skillsVisibility:workingDirectory:tools:defaultSlot:maxConcurrentAgents:maxDepth:maxRetainedRuns:budget:tracer:logger:metricsFactory:inlineSettleGrace:runEventObserver:callerMail:instructionsPreamble:runTemplateContext:sandboxProbe:)``
    /// tells each parameter. `skillsTool` must be the tool that
    /// ``makeSkillsTool(skills:selectionModel:catalogCharacterLimit:visibility:sandboxProbe:)``
    /// made from `skills` and `skillsVisibility`. The init adds it to `tools`
    /// under its name. `selectionModel` is the model of the selection tier of
    /// `find agents`, and the default is `nil`. Give the model that made
    /// `skillsTool`, thus both tools choose with one model.
    ///
    /// A value out of its range, and a `skills` entry in `tools`, are
    /// programmer errors and stop the process.
    init(
        profile: LanguageModelProfile,
        skills: SkillsRegistry,
        skillsTool: SkillsCatalogTool,
        skillsVisibility: @escaping SkillsVisibility,
        selectionModel: (any FoundationModels.LanguageModel)? = nil,
        workingDirectory: URL,
        tools: ToolCatalog,
        defaultSlot: ModelSlot,
        maxConcurrentAgents: Int,
        maxDepth: Int,
        maxRetainedRuns: Int,
        budget: @escaping BudgetFactory,
        tracer: (any Tracer)?,
        logger: Logger?,
        metricsFactory: (any MetricsFactory)?,
        inlineSettleGrace: TimeInterval,
        runEventObserver: RunEventObserver? = nil,
        callerMail: CallerMail? = nil,
        instructionsPreamble: String? = nil,
        runTemplateContext: RunTemplateContext? = nil
    ) {
        precondition(
            ModelMatch.generationSlots.contains { $0.slot == defaultSlot },
            "defaultSlot must be .standard or .flash")
        precondition(maxConcurrentAgents >= 1, "maxConcurrentAgents must be one or more")
        precondition(maxDepth >= 1, "maxDepth must be one or more")
        precondition(maxRetainedRuns >= 0, "maxRetainedRuns must be zero or more")
        precondition(
            !tools.names.contains(skillsTool.name),
            "tools must not hold a '\(skillsTool.name)' entry: the environment adds the skills tool")
        var catalog = tools
        catalog.register(skillsTool.name) { skillsTool }
        self.profile = profile
        self.skills = skills
        self.skillsTool = skillsTool
        self.skillsVisibility = skillsVisibility
        self.selectionModel = selectionModel
        self.workingDirectory = workingDirectory
        self.tools = catalog
        self.defaultSlot = defaultSlot
        self.maxConcurrentAgents = maxConcurrentAgents
        self.maxDepth = maxDepth
        self.maxRetainedRuns = maxRetainedRuns
        self.budget = budget
        self.tracer = tracer
        self.logger = logger
        self.metricsFactory = metricsFactory
        self.inlineSettleGrace = max(0, inlineSettleGrace)
        self.runEventObserver = runEventObserver
        self.callerMail = callerMail
        self.instructionsPreamble = instructionsPreamble
        self.runTemplateContext = runTemplateContext
    }
}

extension AgentEnvironment {
    /// The `skills:` preload of a main session: the skills registry of the
    /// environment, with the visibility rule of its `skills` tool.
    var skillsPreload: AgentSkillsPreload {
        skillsPreload(templateContext: nil)
    }

    /// The `skills:` preload of one run.
    ///
    /// - Parameter templateContext: The template context of the run
    ///   (``runTemplateContext``), or `nil` for the values of the skills
    ///   registry.
    /// - Returns: The preload over the skills registry, or over a view of it
    ///   that renders each skill with `templateContext`.
    func skillsPreload(templateContext: [String: TemplateValue]?) -> AgentSkillsPreload {
        AgentSkillsPreload(
            skills: templateContext.map(skills.with(templateContext:)) ?? skills, isVisible: skillsVisibility)
    }

    /// Gives the tools of one run with a `skills` tool of the run in place of
    /// the shared ``skillsTool``.
    ///
    /// The tool of the run shares the index, the reload follow and the
    /// description of the shared tool, and renders each skill with
    /// `templateContext`. A tool with a different name does not change.
    ///
    /// - Parameters:
    ///   - tools: The resolved tools of the run.
    ///   - templateContext: The template context of the run
    ///     (``runTemplateContext``).
    /// - Returns: The tools, in the same order.
    /// - Throws: ``AgentRunFailure/toolsFailed(_:)`` when the tool of the run
    ///   cannot be made.
    func tools(
        _ tools: [any Tool], withSkillsTemplateContext templateContext: [String: TemplateValue]
    ) throws(AgentRunFailure) -> [any Tool] {
        do {
            return try tools.map { tool in
                tool.name == skillsTool.name ? try skillsTool.with(templateContext: templateContext) : tool
            }
        } catch {
            throw .toolsFailed(String(describing: error))
        }
    }
}
