/// The reason that an agent run failed (plan.md §12).
public enum AgentRunFailure: Error, Sendable, Equatable {
    /// The render of the body at run start failed (plan.md §4.3 step 3). The
    /// text is the description of the render error: for example a template
    /// that Stencil cannot parse, a construct that the untrusted render
    /// refuses, or an include of a partial that no layer in scope holds.
    case bodyRenderFailed(String)
}
