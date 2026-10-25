import Foundation
import FoundationModels
import FoundationModelsAgents
import FoundationModelsRouter
import Synchronization

/// A tool that gives a secret word, and counts its calls.
///
/// Only the tool knows the word, thus an agent that answers with the word
/// used the tool.
final class LiveWordTool: Tool {
    /// The tool takes no arguments.
    @Generable
    struct Arguments {}

    /// The name of the tool in the tool catalog and in an agent file.
    static let toolName = "secret_word"

    /// The word that the tool gives.
    static let word = "MANGO"

    /// The name of the tool.
    let name = toolName

    /// The description of the tool.
    let description = "Gives the secret word."

    /// The count of calls.
    private let calls = Mutex(0)

    /// The count of calls of the tool.
    var callCount: Int {
        calls.withLock { $0 }
    }

    /// Counts the call, and gives the word.
    ///
    /// - Parameter arguments: The empty arguments.
    /// - Returns: A sentence that holds ``word``.
    func call(arguments: Arguments) async throws -> String {
        calls.withLock { $0 += 1 }
        return "The secret word is \(Self.word)."
    }
}

/// A tool that holds its call until the test opens it.
///
/// The generation queue of a model runs one submission at a time, and a
/// submission holds its place while a tool call waits. Thus a held call keeps
/// the run in operation, and keeps its slot busy.
final class LiveHoldTool: Tool {
    /// The tool takes no arguments.
    @Generable
    struct Arguments {}

    /// The name of the tool in the tool catalog and in an agent file.
    static let toolName = "hold"

    /// The word that the tool gives when it lets a call end.
    static let word = "APPLE"

    /// The name of the tool.
    let name = toolName

    /// The description of the tool.
    let description = "Waits for the signal to continue, then gives the word."

    /// The record of the calls of the tool, and of the tasks that wait.
    private struct Record {
        /// `true` after the first call came.
        var hasArrival = false

        /// `true` after ``LiveHoldTool/open()``.
        var isOpen = false

        /// The id that the next wait gets.
        var nextID = 0

        /// Each task that waits in ``LiveHoldTool/waitForArrival(orEndOf:)``,
        /// by the id of its wait.
        var arrivalWaiters: [Int: CheckedContinuation<Bool, Never>] = [:]

        /// The id of each arrival wait whose run ended before the wait
        /// started.
        var endedArrivalWaits: Set<Int> = []

        /// Each call that waits for ``LiveHoldTool/open()``, by the id of
        /// its wait.
        var openWaiters: [Int: CheckedContinuation<Void, any Error>] = [:]

        /// The id of each call wait that was cancelled before the wait
        /// started.
        var cancelledOpenWaits: Set<Int> = []

        /// Gives a new wait id.
        ///
        /// - Returns: The id.
        mutating func takeID() -> Int {
            defer { nextID += 1 }
            return nextID
        }
    }

    /// The record, under a lock.
    private let state = Mutex(Record())

    /// Lets each held call and each later call end.
    func open() {
        let waiters = state.withLock { record in
            record.isOpen = true
            defer { record.openWaiters = [:] }
            return Array(record.openWaiters.values)
        }
        for waiter in waiters {
            waiter.resume()
        }
    }

    /// Waits until a call has come, or until `run` ends. Thus a model that
    /// never calls the tool cannot make the test wait for ever.
    ///
    /// The wait starts a task that waits for the end of `run`. The test does
    /// not cancel that task, because a cancel of a task in `result()` cancels
    /// the run. The task ends when the run ends.
    ///
    /// - Parameter run: The run that must call the tool.
    /// - Returns: `true` when a call came, `false` when `run` ended first.
    func waitForArrival(orEndOf run: AgentRun) async -> Bool {
        let id = state.withLock { $0.takeID() }
        Task {
            _ = try? await run.result()
            self.endArrivalWait(id)
        }
        return await withCheckedContinuation { continuation in
            let answer: Bool? = state.withLock { record in
                if record.hasArrival { return true }
                if record.endedArrivalWaits.remove(id) != nil { return false }
                record.arrivalWaiters[id] = continuation
                return nil
            }
            if let answer {
                continuation.resume(returning: answer)
            }
        }
    }

    /// Ends the arrival wait `id` with `false`, because its run ended. When
    /// the wait did not start yet, the record keeps the id, and the wait
    /// ends at once when it starts.
    ///
    /// - Parameter id: The id of the arrival wait.
    private func endArrivalWait(_ id: Int) {
        let waiter = state.withLock { record in
            guard let waiter = record.arrivalWaiters.removeValue(forKey: id) else {
                record.endedArrivalWaits.insert(id)
                return CheckedContinuation<Bool, Never>?.none
            }
            return waiter
        }
        waiter?.resume(returning: false)
    }

    /// Waits until the test opens the tool, then gives the word.
    ///
    /// - Parameter arguments: The empty arguments.
    /// - Returns: A sentence that holds ``word``.
    /// - Throws: `CancellationError` when the run is cancelled.
    func call(arguments: Arguments) async throws -> String {
        let (id, arrivalWaiters) = state.withLock { record in
            record.hasArrival = true
            defer { record.arrivalWaiters = [:] }
            return (record.takeID(), Array(record.arrivalWaiters.values))
        }
        for waiter in arrivalWaiters {
            waiter.resume(returning: true)
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let answer: Result<Void, any Error>? = state.withLock { record in
                    if record.isOpen { return .success(()) }
                    if record.cancelledOpenWaits.remove(id) != nil { return .failure(CancellationError()) }
                    record.openWaiters[id] = continuation
                    return nil
                }
                if let answer {
                    continuation.resume(with: answer)
                }
            }
        } onCancel: {
            cancelOpenWait(id)
        }
        return "Continue now. The word is \(Self.word)."
    }

    /// Ends the call wait `id` with `CancellationError`. When the wait did
    /// not start yet, the record keeps the id, and the wait ends at once when
    /// it starts.
    ///
    /// - Parameter id: The id of the call wait.
    private func cancelOpenWait(_ id: Int) {
        let waiter = state.withLock { record in
            guard let waiter = record.openWaiters.removeValue(forKey: id) else {
                record.cancelledOpenWaits.insert(id)
                return CheckedContinuation<Void, any Error>?.none
            }
            return waiter
        }
        waiter?.resume(throwing: CancellationError())
    }
}

/// An `agents` tool that keeps the `ToolContext` of each call, and then
/// gives the call to the real tool.
///
/// `check agent` answers only for a run of the caller, and the caller is the
/// session of `ToolContext.current`. A test binds a kept context with
/// `ToolContext.$current.withValue(_:operation:)`, and then calls
/// `check agent` as that session, with no model turn.
final class LiveAgentsToolProbe: Tool {
    /// The arguments of the real tool.
    typealias Arguments = GeneratedContent

    /// The plain-text answer of the real tool.
    typealias Output = String

    /// The real `agents` tool.
    private let wrapped: AgentsTool

    /// The context of each call, in call order.
    private let contexts = Mutex<[ToolContext]>([])

    /// Makes a probe over `tool`.
    ///
    /// - Parameter tool: The real `agents` tool.
    init(wrapping tool: AgentsTool) {
        wrapped = tool
    }

    /// The name of the real tool.
    var name: String {
        wrapped.name
    }

    /// The description of the real tool.
    var description: String {
        wrapped.description
    }

    /// The schema of the real tool.
    var parameters: GenerationSchema {
        wrapped.parameters
    }

    /// The schema choice of the real tool.
    var includesSchemaInInstructions: Bool {
        wrapped.includesSchemaInInstructions
    }

    /// The context of each call that a Router session made, in call order.
    var callContexts: [ToolContext] {
        contexts.withLock { $0 }
    }

    /// Keeps the context of the call, then calls the real tool.
    ///
    /// - Parameter arguments: The arguments of the call.
    /// - Returns: The answer of the real tool.
    /// - Throws: The error of the real tool.
    func call(arguments: GeneratedContent) async throws -> String {
        if let context = ToolContext.current {
            contexts.withLock { $0.append(context) }
        }
        return try await wrapped.call(arguments: arguments)
    }
}

/// The probe mounts each call as the real tool does: each part gives the
/// part of the real tool.
extension LiveAgentsToolProbe: BackgroundTool {
    /// The mount of one call of the real tool.
    ///
    /// - Parameter arguments: The arguments of the call.
    /// - Returns: The mount of the operation that `arguments` names.
    func mount(for arguments: GeneratedContent) -> ToolMount? {
        wrapped.mount(for: arguments)
    }

    /// The description of one call of the real tool, which the pending text
    /// names the call by.
    ///
    /// - Parameter arguments: The arguments of the call.
    /// - Returns: The description of the real tool, or `nil`.
    func callDescription(for arguments: GeneratedContent) -> String? {
        wrapped.callDescription(for: arguments)
    }

    /// The `next` text of the real tool.
    ///
    /// - Parameters:
    ///   - completionToken: The completion token of the call.
    ///   - description: The description of the call.
    /// - Returns: The text.
    func collectInstruction(forCompletionToken completionToken: String, describing description: String) -> String {
        wrapped.collectInstruction(forCompletionToken: completionToken, describing: description)
    }

    /// The canceler of the real tool.
    ///
    /// - Parameter completionToken: The completion token of the call.
    /// - Returns: The canceler.
    func canceler(forCompletionToken completionToken: String) -> (@Sendable () async -> OperationOutcome)? {
        wrapped.canceler(forCompletionToken: completionToken)
    }
}

extension ToolCatalog {
    /// Makes a catalog that gives the same instance of each tool.
    ///
    /// - Parameter tools: The tools, each under its own name.
    /// - Returns: The catalog.
    static func holding(_ tools: [any Tool]) -> ToolCatalog {
        tools.reduce(into: ToolCatalog()) { catalog, tool in
            catalog.register(tool.name) { tool }
        }
    }
}
