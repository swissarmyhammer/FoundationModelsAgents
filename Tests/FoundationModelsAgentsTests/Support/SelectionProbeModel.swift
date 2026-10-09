import FoundationModels
import Synchronization

/// The count of the generation calls that a ``SelectionProbeModel`` got.
///
/// `Mutex` guards the count, thus the `Sendable` conformance is checked.
final class SelectionProbeCalls: Sendable {
    /// The count of the calls.
    private let calls = Mutex(0)

    /// The count of the calls so far.
    var count: Int {
        calls.withLock { $0 }
    }

    /// Adds one call to the count.
    func record() {
        calls.withLock { $0 += 1 }
    }
}

/// The error of each generation call of a ``SelectionProbeModel``.
enum SelectionProbeError: Error {
    /// The probe gives no answer. The selection tier then gives the rank of
    /// the retrieval tier.
    case noAnswer
}

/// A selection model of the `skills` tool that counts its generation calls
/// and answers none.
///
/// The selection tier asks for a `Generable` type, thus the model has the
/// guided generation capability. Each call adds one to ``calls`` and fails.
struct SelectionProbeModel: LanguageModel {
    /// The executor that counts each call.
    typealias Executor = SelectionProbeExecutor

    /// The count of the generation calls.
    let calls: SelectionProbeCalls

    /// Guided generation, thus a session can ask for a `Generable` type.
    var capabilities: LanguageModelCapabilities {
        LanguageModelCapabilities([.guidedGeneration])
    }

    /// The cache key of the executor: the identity of the count.
    var executorConfiguration: SelectionProbeExecutor.Configuration {
        SelectionProbeExecutor.Configuration(calls: ObjectIdentifier(calls))
    }
}

/// The executor of ``SelectionProbeModel``: it counts the call, then fails.
struct SelectionProbeExecutor: LanguageModelExecutor {
    /// The cache key that the SDK makes and reuses the executor by.
    struct Configuration: Sendable, Hashable {
        /// The identity of the count of the model.
        let calls: ObjectIdentifier
    }

    /// The model that this executor runs for.
    typealias Model = SelectionProbeModel

    /// Makes an executor. The configuration holds nothing that the executor
    /// reads: the count arrives with the model on each call.
    ///
    /// - Parameter configuration: The cache key.
    /// - Throws: Never. `throws` comes from the `LanguageModelExecutor`
    ///   requirement.
    init(configuration: Configuration) throws {}

    /// Counts the call, and gives no answer.
    ///
    /// - Parameters:
    ///   - request: The generation request.
    ///   - model: The model with the count.
    ///   - channel: The channel that gets no output.
    /// - Throws: ``SelectionProbeError/noAnswer`` for each call.
    func respond(
        to request: LanguageModelExecutorGenerationRequest,
        model: SelectionProbeModel,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        model.calls.record()
        throw SelectionProbeError.noAnswer
    }
}
