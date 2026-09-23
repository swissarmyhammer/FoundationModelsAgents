import Foundation
import FoundationModelsRouter
import HuggingFace
import MLXHuggingFace
import MLXLMCommon
import Tokenizers

/// The real profile of `agents-demo --chat` and `agents-demo --fan-out`
/// (plan.md §12, §13).
///
/// The two modes need a resolved `LanguageModelProfile`. The example makes a
/// `Router` over the live model loader, and resolves ``definition`` with it.
/// The first resolve downloads the models from Hugging Face. The other modes
/// of the example resolve no profile.
enum AgentsDemoProfile {
    /// The name of the recordings folder in the temporary directory.
    static let recordingsFolderName = "agents-demo-recordings"

    /// The profile that the example resolves: small `mlx-community` models.
    ///
    /// The `standard` and `flash` slots have different models. Thus each slot
    /// has its own generation gate, and a turn on one slot does not wait for
    /// a turn on the other slot.
    static let definition = ProfileDefinition(
        name: "agents-demo",
        description: "Small local models for the agents-demo example.",
        standard: ["mlx-community/Qwen3-4B-4bit"],
        flash: ["mlx-community/Qwen3-1.7B-4bit"],
        embedding: ["mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ"])

    /// The recordings root of the router: a folder in the temporary
    /// directory.
    static var recordingsDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(recordingsFolderName, isDirectory: true)
    }

    /// Makes a router over the live model loader.
    ///
    /// The router records each session under ``recordingsDirectory``. The
    /// agent runs post their final messages into these recordings.
    ///
    /// - Returns: The router. The caller keeps it while it uses the profile.
    static func makeRouter() -> Router {
        Router(
            recordingsDir: recordingsDirectory,
            loader: LiveModelLoader(
                downloader: #hubDownloader(),
                tokenizerLoader: #huggingFaceTokenizerLoader()))
    }

    /// Resolves ``definition`` with `router`.
    ///
    /// - Parameter router: The router of the profile.
    /// - Returns: The resolved, resident profile. The caller keeps it while
    ///   it uses the sessions of the profile.
    /// - Throws: The error of `Router.resolve(profile:reporting:)`.
    static func resolve(with router: Router) async throws -> LanguageModelProfile {
        try await router.resolve(profile: definition, reporting: ResolutionProgress())
    }
}
