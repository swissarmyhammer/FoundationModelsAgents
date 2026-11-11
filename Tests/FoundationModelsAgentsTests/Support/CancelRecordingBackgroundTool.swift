import Foundation
import FoundationModels
import FoundationModelsExtras
import Synchronization

/// A background tool whose run holds on a gate, as a long shell command
/// holds, and that records a cancel of its run.
struct CancelRecordingBackgroundTool: Tool, BackgroundTool {
    /// The arguments of the tool: one text.
    @Generable
    struct Arguments {
        /// A text that the tool ignores.
        let text: String
    }

    /// The count of the runs of the tool that were cancelled at the gate.
    final class Record: Sendable {
        /// The count.
        private let count = Mutex(0)

        /// The count of the cancelled runs.
        var cancels: Int { count.withLock { $0 } }

        /// Counts one cancelled run.
        func recordCancel() {
            count.withLock { $0 += 1 }
        }
    }

    /// The name of the tool.
    let name: String

    /// The description of the tool.
    let description = "A background tool that holds its run until a gate opens, and records a cancel."

    /// The mount of the tool: background.
    let mount: ToolMount? = ToolMount(mode: .background)

    /// No wait for the run: each call answers with a pending envelope.
    let inlineSettleGrace: TimeInterval = 0

    /// The gate that holds the run.
    let gate: ScriptedGate

    /// The record of the cancels.
    let record: Record

    /// Waits on the gate. A cancel at the gate is recorded, then rethrown.
    ///
    /// - Parameter arguments: The arguments, which the tool ignores.
    /// - Returns: "done".
    /// - Throws: `CancellationError` when the run is cancelled at the gate.
    func call(arguments: Arguments) async throws -> String {
        do {
            try await gate.wait()
        } catch {
            record.recordCancel()
            throw error
        }
        return "done"
    }
}
