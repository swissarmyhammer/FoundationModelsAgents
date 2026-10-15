import FoundationModels
import FoundationModelsExtras
import FoundationModelsRouter
import Synchronization
import ULID

/// A tool whose body asks the user one question through its `ToolContext`
/// (`ToolContext.elicit(_:)`), keeps the answer, and gives the answer as its
/// output.
///
/// In a headless session the question ends at once with a cancel that gives
/// `RunPlane.noUserPresentReason`. In an interactive session the body waits
/// until a caller of `respond(elicitationId:response:)` answers.
struct AskingTool: Tool {
    /// The arguments of the tool: one text.
    @Generable
    struct Arguments {
        /// A text that the tool ignores.
        let text: String
    }

    /// The question that the tool asks.
    static let question = "Which file do you want to review?"

    /// The name of the tool.
    let name: String

    /// The description of the tool.
    let description = "A tool that asks the user one question, then gives the answer."

    /// The answers that the tool got, in order.
    let answers: AskedAnswers

    /// Asks ``question``, keeps the answer in ``answers``, and gives it.
    ///
    /// - Parameter arguments: The arguments, which the tool ignores.
    /// - Returns: The action of the answer and its reason.
    /// - Throws: The error of `ToolContext.elicit(_:)` for a malformed request.
    func call(arguments: Arguments) async throws -> String {
        guard let context = ToolContext.current else {
            return "The tool has no context."
        }
        let response = try await context.elicit(
            ElicitationRequest(
                message: Self.question, elicitationId: ULID(),
                requestedSchema: ElicitationRequestedSchema(properties: [:])))
        answers.record(response)
        return "The answer was \(response.action.rawValue): \(response.reason ?? "no reason")."
    }
}

/// The answers that an ``AskingTool`` got, in order.
///
/// A class, because the tool and the test hold the same record. A `Mutex`
/// guards the answers, thus the `Sendable` conformance is compiler-checked.
final class AskedAnswers: Sendable {
    /// The answers, in order.
    private let responses = Mutex<[ElicitationResponse]>([])

    /// The answers so far, in order.
    var all: [ElicitationResponse] {
        responses.withLock { $0 }
    }

    /// Adds one answer.
    ///
    /// - Parameter response: The answer.
    func record(_ response: ElicitationResponse) {
        responses.withLock { $0.append(response) }
    }
}

/// The count of the question events that the runs sent to the observer of
/// the host (`SessionEvent.elicitationRequested`).
///
/// A class, because the observer and the test hold the same count. A `Mutex`
/// guards the count, thus the `Sendable` conformance is compiler-checked.
final class QuestionEventCount: Sendable {
    /// The count.
    private let count = Mutex(0)

    /// The count so far.
    var value: Int {
        count.withLock { $0 }
    }

    /// Adds one when `output` is a question event.
    ///
    /// - Parameter output: A session output of a run.
    func observe(_ output: SessionOutput) {
        if case .elicitationRequested = output.event {
            count.withLock { $0 += 1 }
        }
    }
}
