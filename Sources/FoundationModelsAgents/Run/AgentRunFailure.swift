import FoundationModels

/// The reason that an agent run failed.
///
/// The first four cases occur before the run makes its session. A run that
/// fails for one of them has no session and no recording directory. The last
/// four cases occur in the answers of the run.
public enum AgentRunFailure: Error, Sendable, Equatable {
    /// The render of the body at run start failed. The text is the
    /// description of the render error: for example a template that Stencil
    /// cannot parse, a construct that the untrusted render refuses, or an
    /// include of a partial that no layer in scope holds.
    case bodyRenderFailed(String)

    /// The render of a skill of the `skills` key failed at run start (the
    /// `skills:` preload). `skill` is the name of the skill. `description`
    /// is the description of the render error of the skills registry.
    case skillRenderFailed(skill: String, description: String)

    /// An `AGENTS.md` file of the working directory is not readable text.
    /// The text is the description of the read error.
    case agentsMdUnreadable(String)

    /// The run could not make its tools. The text is the description of the
    /// error of the tool factory.
    case toolsFailed(String)

    /// The context of the session was full, and the compaction of the
    /// Router did not make enough space. The text is the description of the
    /// model error.
    case contextOverflow(String)

    /// The model of the session failed in the turn. The text is the
    /// description of the error.
    case modelFailed(String)

    /// The run went above the `maxTurns` limit of its agent. The run counts
    /// one turn for each pass of the control loop, in the answer of its task
    /// prompt and in each answer to the final message of a run that it
    /// started. `partial` is the text of the answer when the count went above
    /// the limit.
    case hitMaxTurns(partial: String)

    /// The Router held the final messages of the runs that this run started,
    /// and started no answer for them (`SessionEvent.mailDeliveryPaused`).
    /// The run cannot finish without these answers. The text is the
    /// description of the hold.
    case mailDeliveryPaused(String)

    /// The reason of the failure as a clause for a model or a person: for
    /// example "the model failed: <description>". It has no period at the
    /// end, thus a sentence can hold it.
    var reason: String {
        switch self {
        case .bodyRenderFailed(let text):
            "the body of the agent did not render: \(text)"
        case .skillRenderFailed(let skill, let text):
            "the skill '\(skill)' of the skills key did not render: \(text)"
        case .agentsMdUnreadable(let text):
            "an AGENTS.md file is not readable: \(text)"
        case .toolsFailed(let text):
            "the tools of the agent could not be made: \(text)"
        case .contextOverflow(let text):
            "the context of the session is full: \(text)"
        case .modelFailed(let text):
            "the model failed: \(text)"
        case .hitMaxTurns(let partial):
            "the agent used more turns than its maxTurns limit; its text so far: \(partial)"
        case .mailDeliveryPaused(let text):
            "the session did not deliver the final messages of the agents that it started: \(text)"
        }
    }

    /// Gives the failure for an error that the turn of a run threw.
    ///
    /// An ``AgentRunFailure`` stays as it is: for example
    /// ``hitMaxTurns(partial:)`` from the turn count.
    /// `LanguageModelError.contextSizeExceeded` gives ``contextOverflow(_:)``.
    /// Each other error gives ``modelFailed(_:)``.
    ///
    /// - Parameter error: The error of the turn. It is not a cancellation.
    /// - Returns: The failure of the run.
    static func turnFailure(for error: any Error) -> AgentRunFailure {
        if let failure = error as? AgentRunFailure {
            return failure
        }
        let text = String(describing: error)
        if case LanguageModelError.contextSizeExceeded = error {
            return .contextOverflow(text)
        }
        return .modelFailed(text)
    }
}
