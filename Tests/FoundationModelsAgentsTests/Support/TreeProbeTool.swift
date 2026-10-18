import FoundationModels
import FoundationModelsExtras
import Synchronization
import ULID

/// A tool whose body reads the session tree of its `ToolContext`, begins one
/// `WorkKind.shellCommand` lease through that context, and holds the lease
/// until its gate opens.
///
/// A test reads each call from ``TreeProbeRecord``: the session, the parent
/// session and the root session of the call, and the item of the lease.
struct TreeProbeTool: Tool {
    /// The arguments of the tool: one text.
    @Generable
    struct Arguments {
        /// A text that the tool ignores.
        let text: String
    }

    /// The facts of one call.
    struct Call: Sendable, Equatable {
        /// The session of the call.
        let sessionID: ULID

        /// The parent session of the call, or `nil` at the root.
        let parentSessionID: ULID?

        /// The root session of the tree of the call.
        let rootSessionID: ULID

        /// The lease that the call held.
        let lease: WorkItem
    }

    /// The name of the tool.
    let name: String

    /// The description of the tool.
    let description = "A tool that reads its session tree and holds one lease."

    /// The record of the calls.
    let record: TreeProbeRecord

    /// The gate that holds the lease open, or `nil` to end the lease at once.
    let gate: ScriptedGate?

    /// Records the facts of the call, holds the lease until the gate opens,
    /// and ends the lease.
    ///
    /// - Parameter arguments: The arguments, which the tool ignores.
    /// - Returns: A short text.
    /// - Throws: `CancellationError` when the call is cancelled at the gate.
    func call(arguments: Arguments) async throws -> String {
        guard let context = ToolContext.current else {
            return "The tool has no context."
        }
        let lease = context.beginBackgroundWork(.shellCommand, id: name)
        defer { lease.end() }
        record.add(
            Call(
                sessionID: context.sessionID, parentSessionID: context.parentSessionID,
                rootSessionID: context.rootSessionID, lease: lease.item))
        try await gate?.wait()
        return "The probe is done."
    }
}

/// The calls of the ``TreeProbeTool`` instances of one test, in order.
///
/// A class, because the tools and the test hold the same record. A `Mutex`
/// guards the calls, thus the `Sendable` conformance is compiler-checked.
final class TreeProbeRecord: Sendable {
    /// The calls, in order.
    private let calls = Mutex<[TreeProbeTool.Call]>([])

    /// The calls so far, in order.
    var all: [TreeProbeTool.Call] {
        calls.withLock { $0 }
    }

    /// Adds one call.
    ///
    /// - Parameter call: The facts of the call.
    func add(_ call: TreeProbeTool.Call) {
        calls.withLock { $0.append(call) }
    }
}
