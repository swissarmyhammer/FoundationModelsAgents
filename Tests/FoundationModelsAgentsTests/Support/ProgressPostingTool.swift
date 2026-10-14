import FoundationModels
import FoundationModelsExtras

/// A tool whose body posts one `.progress` event through the sink of its
/// `ToolContext`, holds until a gate opens, and then gives a fixed output.
///
/// The session puts each posted progress event in its mail queue as run
/// mail. Progress mail starts no submission. Thus a progress event that the
/// body posts in the last answer of a run stays in the queue after that
/// answer ends. `progress(_:plan:)` returns only after the event is in the
/// queue, thus the queue holds the mail when the body arrives at the gate.
struct ProgressPostingTool: Tool {
    /// The arguments of the tool: one text.
    @Generable
    struct Arguments {
        /// A text that the tool ignores.
        let text: String
    }

    /// The name of the tool.
    let name: String

    /// The description of the tool.
    let description = "A tool that posts one progress event, then holds until a gate opens."

    /// The detail of the progress event.
    let progressDetail: String

    /// The output of the tool.
    let output: String

    /// The gate that holds the body after the progress event.
    let gate: ScriptedGate

    /// Posts the progress event, waits on the gate, and gives the output.
    ///
    /// - Parameter arguments: The arguments, which the tool ignores.
    /// - Returns: ``output``.
    /// - Throws: `CancellationError` when the task is cancelled.
    func call(arguments: Arguments) async throws -> String {
        await ToolContext.current?.progress(progressDetail)
        try await gate.wait()
        return output
    }
}
