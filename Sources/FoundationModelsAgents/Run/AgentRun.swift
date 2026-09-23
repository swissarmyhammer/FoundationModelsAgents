import Foundation
import FoundationModelsRouter
import Synchronization
import ULID

/// One delegated task: one agent, one prompt, and one Router session
/// (plan.md §8, §8.1).
///
/// `start` does the synchronous steps before it returns: it renders the
/// body, puts the instructions in order, makes the tools, matches the model,
/// and makes the session. Thus ``id`` is the session id at once. Only the
/// turn runs in the background, and nothing goes to the caller during the
/// turn. The text of the last turn is the result. The run then closes its
/// session, and a finished run holds no session.
///
/// A run whose setup fails has no session. It gets a new ULID, no recording
/// directory, and the state ``AgentRunState/failed(_:)``.
///
/// A class, because the runner and the caller share one run. A `Mutex`
/// guards the state, thus the `Sendable` conformance is compiler-checked.
public final class AgentRun: Sendable {
    /// The state that the lock guards.
    private struct Storage {
        /// The state of the run.
        var state: AgentRunState

        /// The session of the run until the turn ends, then `nil`.
        var session: (any RoutedSession)?

        /// The background task of the turn, or `nil` for a run whose setup
        /// failed. It gives the final state of the run.
        var turn: Task<AgentRunState, Never>?
    }

    /// The id of the run. It is the session id and the name of the
    /// recording directory. A run whose setup failed has a new ULID.
    public let id: ULID

    /// The resolved agent. The run keeps it for its whole life.
    public let agent: AgentDefinition

    /// The session of the caller, or `nil` for a host-driven run.
    public let caller: ULID?

    /// The depth of the run. A host-started run has depth one.
    public let depth: Int

    /// The directory of the recording of the session:
    /// `<recordingsDir>/<routerId>/<id>`. It is `nil` for a run whose setup
    /// failed.
    public let recordingDirectory: URL?

    /// The slot of the session, or `nil` for a run whose setup failed.
    let slot: ModelSlot?

    /// The mutable state of the run.
    private let storage: Mutex<Storage>

    /// The state of the run.
    public var state: AgentRunState {
        storage.withLock { $0.state }
    }

    /// The session that the run holds: the session of the turn in operation,
    /// or `nil` after the turn ends. The run never gives the session to the
    /// caller.
    var heldSession: (any RoutedSession)? {
        storage.withLock { $0.session }
    }

    /// Makes a run.
    ///
    /// - Parameters:
    ///   - id: The id of the run.
    ///   - request: The inputs of the run.
    ///   - made: The session and its slot, or `nil` when the setup failed.
    ///   - state: The first state of the run.
    private init(id: ULID, request: AgentRunRequest, made: AgentSessionMaker.Made?, state: AgentRunState) {
        self.id = id
        self.agent = request.definition
        self.caller = request.context?.sessionID
        self.depth = request.depth
        self.recordingDirectory = made?.session.recordingDirectory
        self.slot = made?.slot
        self.storage = Mutex(Storage(state: state, session: made?.session, turn: nil))
    }

    /// Starts the run of `request` (plan.md §8 steps 1 to 6 and 8).
    ///
    /// The setup is done when the call returns, thus the run has its id.
    /// The turn then runs in the background.
    ///
    /// - Parameters:
    ///   - request: The inputs of the run.
    ///   - environment: The dependencies and the limits of the runs.
    ///   - renderer: Renders the body of the agent.
    /// - Returns: The run, in ``AgentRunState/running``, or in
    ///   ``AgentRunState/failed(_:)`` when the setup failed.
    static func start(
        _ request: AgentRunRequest, environment: AgentEnvironment, renderer: AgentBodyRenderer
    ) async -> AgentRun {
        let made: AgentSessionMaker.Made
        do {
            made = try await AgentSessionMaker(environment: environment, renderer: renderer)
                .makeSession(for: request)
        } catch {
            return AgentRun(id: ULID(), request: request, made: nil, state: .failed(error))
        }
        let run = AgentRun(id: made.session.id, request: request, made: made, state: .running)
        run.startTurn(on: made.session, prompt: request.prompt)
        return run
    }

    /// Waits for the run to end, and gives its result.
    ///
    /// - Returns: The text of the last turn.
    /// - Throws: The ``AgentRunFailure`` of a failed run, or
    ///   `CancellationError` for a cancelled run.
    public func result() async throws -> String {
        let turn = storage.withLock { $0.turn }
        let final = await turn?.value ?? state
        switch final {
        case .finished(let text):
            return text
        case .failed(let failure):
            throw failure
        case .cancelled, .running:
            throw CancellationError()
        }
    }

    /// Cancels the turn of the run. The run then closes its session and goes
    /// to ``AgentRunState/cancelled``. A run that ended stays as it is.
    public func cancel() {
        storage.withLock { $0.turn }?.cancel()
    }

    /// Starts the background task that drives the one turn of the run.
    ///
    /// The task is detached, thus it does not take the `ToolContext` of the
    /// tool call that started the run. The tools of the session bind their
    /// own contexts.
    ///
    /// - Parameters:
    ///   - session: The session of the run.
    ///   - prompt: The prompt of the turn.
    private func startTurn(on session: any RoutedSession, prompt: String) {
        let turn = Task.detached {
            let final = await Self.drive(session, prompt: prompt)
            await session.close()
            self.end(in: final)
            return final
        }
        storage.withLock { $0.turn = turn }
    }

    /// Records the final state, and lets go of the session.
    ///
    /// - Parameter final: The final state of the run.
    private func end(in final: AgentRunState) {
        storage.withLock { storage in
            storage.state = final
            storage.session = nil
        }
    }

    /// Drives one turn with `prompt`, and collects the text of the answer.
    ///
    /// - Parameters:
    ///   - session: The session of the run.
    ///   - prompt: The prompt of the turn.
    /// - Returns: The final state: ``AgentRunState/finished(_:)`` with the
    ///   text of the turn, ``AgentRunState/cancelled`` for a cancelled turn,
    ///   or ``AgentRunState/failed(_:)`` for an error of the turn.
    private static func drive(_ session: any RoutedSession, prompt: String) async -> AgentRunState {
        var text = TurnText()
        do {
            for try await event in await session.streamEvents(to: prompt) {
                text.apply(event)
            }
        } catch {
            return Task.isCancelled || error is CancellationError
                ? .cancelled : .failed(AgentRunFailure.turnFailure(for: error))
        }
        return Task.isCancelled ? .cancelled : .finished(text.value)
    }
}

/// The text of the answer of one turn, collected from its events.
///
/// A ``SessionEvent/textReset`` clears the text that came before it.
private struct TurnText {
    /// The text so far.
    private(set) var value = ""

    /// Applies one event of the turn.
    ///
    /// - Parameter event: The event.
    mutating func apply(_ event: SessionEvent) {
        if case .textDelta(let fragment) = event {
            value += fragment
        }
        if case .textReset = event {
            value = ""
        }
    }
}
