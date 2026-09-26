import Foundation
import FoundationModelsRouter

/// Reads the tool output that a model got from a background tool.
///
/// The Router answers each call of a background tool with a
/// `PendingRunEnvelope`. A call that settled inside the grace of the tool
/// carries its answer in the `detail` of that envelope.
enum ToolOutputEnvelope {
    /// Gives the answer that `output` holds.
    ///
    /// - Parameter output: The text of a tool output.
    /// - Returns: The `detail` of a settled envelope, or `output` itself for
    ///   each other text.
    static func answer(of output: String) -> String {
        let envelope = try? JSONDecoder().decode(PendingRunEnvelope.self, from: Data(output.utf8))
        return envelope?.detail ?? output
    }
}
