import FoundationModels
import FoundationModelsAgents
import FoundationModelsRouter
import Synchronization

/// Waits for a condition with a time limit.
///
/// The live tools use it, thus a tool that waits for another event never
/// waits for ever. When the time limit ends, the tool gives its answer, and
/// the test sees the failed condition in the record of the tool.
enum LivePolling {
    /// The number of milliseconds between two reads of the condition.
    private static let intervalMilliseconds = 100

    /// The time between two reads of the condition.
    private static let interval: Duration = .milliseconds(intervalMilliseconds)

    /// Waits until `condition` is true, or until `timeout` ends.
    ///
    /// - Parameters:
    ///   - timeout: The longest time to wait.
    ///   - condition: The condition to wait for.
    /// - Returns: `true` when the condition became true in the time limit.
    /// - Throws: `CancellationError` when the task is cancelled.
    static func wait(upTo timeout: Duration, until condition: () -> Bool) async throws -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() && clock.now < deadline {
            try await Task.sleep(for: interval)
        }
        return condition()
    }
}

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
/// The Router holds the generation gate of the model for the whole turn,
/// thus a held call keeps the run in operation, and keeps its slot busy.
final class LiveHoldTool: Tool {
    /// The tool takes no arguments.
    @Generable
    struct Arguments {}

    /// The name of the tool in the tool catalog and in an agent file.
    static let toolName = "hold"

    /// The word that the tool gives when it lets a call end.
    static let word = "APPLE"

    /// The number of seconds that a test waits for a run to call the tool.
    private static let arrivalSeconds = 300

    /// The number of seconds that one call waits for ``open()``.
    private static let timeoutSeconds = 600

    /// The longest time that a test waits for a run to call the tool.
    static let arrivalTimeout: Duration = .seconds(arrivalSeconds)

    /// The longest time that one call waits for ``open()``. A test that
    /// fails before it opens the tool stops its runner, and the cancel ends
    /// the wait before this limit.
    private static let timeout: Duration = .seconds(timeoutSeconds)

    /// The name of the tool.
    let name = toolName

    /// The description of the tool.
    let description = "Waits for the signal to continue, then gives the word."

    /// The record of the calls of the tool.
    private struct Record {
        /// The count of calls that came.
        var arrivals = 0

        /// `true` after ``LiveHoldTool/open()``.
        var isOpen = false
    }

    /// The record of the calls, under a lock.
    private let state = Mutex(Record())

    /// Lets each held call and each later call end.
    func open() {
        state.withLock { $0.isOpen = true }
    }

    /// Waits until a call has come.
    ///
    /// - Parameter timeout: The longest time to wait.
    /// - Returns: `true` when a call came in the time limit.
    /// - Throws: `CancellationError` when the task is cancelled.
    func waitForArrival(upTo timeout: Duration) async throws -> Bool {
        try await LivePolling.wait(upTo: timeout) {
            state.withLock { $0.arrivals > 0 }
        }
    }

    /// Waits until the test opens the tool, then gives the word.
    ///
    /// - Parameter arguments: The empty arguments.
    /// - Returns: A sentence that holds ``word``.
    /// - Throws: `CancellationError` when the run is cancelled.
    func call(arguments: Arguments) async throws -> String {
        state.withLock { $0.arrivals += 1 }
        _ = try await LivePolling.wait(upTo: Self.timeout) {
            state.withLock { $0.isOpen }
        }
        return "Continue now. The word is \(Self.word)."
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
