import FoundationModels
@testable import FoundationModelsAgents
import FoundationModelsRouter
import Synchronization

/// A tool that starts an agent run inside its call, with the
/// `ToolContext.current` of the call, as `start agent` will do (plan.md
/// §8.2, §9.2).
///
/// The probe keeps the run and the context, thus the test reads the lineage
/// and posts through the context after the call returns.
final class AgentStartProbe: Tool {
    /// The arguments of the tool: one text.
    @Generable
    struct Arguments {
        /// A text that the tool ignores.
        let text: String
    }

    /// The run that one call started, and the context of that call.
    struct Started: Sendable {
        /// The run.
        let run: AgentRun

        /// The context of the call, or `nil` when the call had none.
        let context: ToolContext?
    }

    /// The name that a scripted step calls the tool by.
    static let toolName = "start-agent-probe"

    /// The name of the tool.
    let name = AgentStartProbe.toolName

    /// The description of the tool.
    let description = "Starts an agent run for the lineage tests."

    /// Starts a run with the context of the call.
    private let startRun: @Sendable (ToolContext?) async throws -> AgentRun

    /// The run of the last call, or `nil` before the first call.
    private let lastStart = Mutex<Started?>(nil)

    /// Makes a probe.
    ///
    /// - Parameter startRun: Starts a run with the context of the call.
    init(startRun: @escaping @Sendable (ToolContext?) async throws -> AgentRun) {
        self.startRun = startRun
    }

    /// The run of the last call and its context, or `nil` before the first
    /// call.
    var started: Started? {
        lastStart.withLock { $0 }
    }

    /// Starts a run with `ToolContext.current`, and keeps it.
    ///
    /// - Parameter arguments: The arguments, which the tool ignores.
    /// - Returns: The id of the run.
    /// - Throws: The error of `startRun`.
    func call(arguments: Arguments) async throws -> String {
        let context = ToolContext.current
        let run = try await startRun(context)
        lastStart.withLock { $0 = Started(run: run, context: context) }
        return run.id.description
    }
}
