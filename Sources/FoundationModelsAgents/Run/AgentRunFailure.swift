import FoundationModels

/// The reason that an agent run failed (plan.md §12).
///
/// The first three cases occur before the run makes its session. A run that
/// fails for one of them has no session and no recording directory. The last
/// two cases occur in the turn of the run.
public enum AgentRunFailure: Error, Sendable, Equatable {
    /// The render of the body at run start failed (plan.md §4.3 step 3). The
    /// text is the description of the render error: for example a template
    /// that Stencil cannot parse, a construct that the untrusted render
    /// refuses, or an include of a partial that no layer in scope holds.
    case bodyRenderFailed(String)

    /// An `AGENTS.md` file of the working directory is not readable text
    /// (plan.md §8 step 3). The text is the description of the read error.
    case agentsMdUnreadable(String)

    /// The run could not make its tools (plan.md §8 step 4). The text is the
    /// description of the error of the tool factory.
    case toolsFailed(String)

    /// The context of the session was full, and the compaction of the
    /// Router did not make enough space. The text is the description of the
    /// model error.
    case contextOverflow(String)

    /// The model of the session failed in the turn. The text is the
    /// description of the error.
    case modelFailed(String)

    /// The reason of the failure as a clause for a model or a person: for
    /// example "the model failed: <description>". It has no period at the
    /// end, thus a sentence can hold it.
    var reason: String {
        switch self {
        case .bodyRenderFailed(let text):
            "the body of the agent did not render: \(text)"
        case .agentsMdUnreadable(let text):
            "an AGENTS.md file is not readable: \(text)"
        case .toolsFailed(let text):
            "the tools of the agent could not be made: \(text)"
        case .contextOverflow(let text):
            "the context of the session is full: \(text)"
        case .modelFailed(let text):
            "the model failed: \(text)"
        }
    }

    /// Gives the failure for an error that the turn of a run threw.
    ///
    /// `LanguageModelError.contextSizeExceeded` gives ``contextOverflow(_:)``.
    /// Each other error gives ``modelFailed(_:)``.
    ///
    /// - Parameter error: The error of the turn. It is not a cancellation.
    /// - Returns: The failure of the run.
    static func turnFailure(for error: any Error) -> AgentRunFailure {
        let text = String(describing: error)
        if case LanguageModelError.contextSizeExceeded = error {
            return .contextOverflow(text)
        }
        return .modelFailed(text)
    }
}
