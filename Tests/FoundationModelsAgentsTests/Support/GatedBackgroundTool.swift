import Foundation
import FoundationModels
import FoundationModelsExtras

/// A background tool whose call answers at once with a pending envelope, and
/// whose run holds until a gate opens, then gives a fixed output.
///
/// The run plane mails the result of the run to the session as run mail, as
/// it does for `runCode`. Thus a test that opens the gate while an answer
/// still runs puts the result mail in the queue before that answer ends.
struct GatedBackgroundTool: Tool, BackgroundTool {
    /// The arguments of the tool: one text.
    @Generable
    struct Arguments {
        /// A text that the tool ignores.
        let text: String
    }

    /// The name of the tool.
    let name: String

    /// The description of the tool.
    let description = "A background tool that holds its run until a gate opens."

    /// The mount of the tool: background.
    let mount: ToolMount? = ToolMount(mode: .background)

    /// No wait for the run: each call answers with a pending envelope.
    let inlineSettleGrace: TimeInterval = 0

    /// The output of the run.
    let output: String

    /// The gate that holds the run.
    let gate: ScriptedGate

    /// Waits on the gate, and gives the output.
    ///
    /// - Parameter arguments: The arguments, which the tool ignores.
    /// - Returns: ``output``.
    /// - Throws: `CancellationError` when the run is cancelled at the gate.
    func call(arguments: Arguments) async throws -> String {
        try await gate.wait()
        return output
    }
}
