import Foundation
import FoundationModelsRouter

/// Makes a resolved `LanguageModelProfile` whose generation slots play a
/// ``ScriptedAgentScript``, with no download and no network.
///
/// `LanguageModelProfile.init` is `package` in Router, thus the profile comes
/// from the public `Router.resolve(profile:reporting:)` over stub seams: a
/// large machine, tiny metadata, and a loader that loads scripted containers.
enum ScriptedProfile {
    /// The model of the `standard` slot.
    static let standardModel: ModelRef = "scripted/standard"

    /// The model of the `flash` slot. It is not ``standardModel``, thus a
    /// test can tell the two slots apart by `chosen`.
    static let flashModel: ModelRef = "scripted/flash"

    /// The model of the `embedding` slot.
    static let embeddingModel: ModelRef = "scripted/embedding"

    /// Resolves a profile whose `standard` and `flash` slots play `script`.
    ///
    /// Each call makes its own router, its own cache directory, and its own
    /// `ModelPool`. A pool gives each model identity one container, and the
    /// first loader to reach an identity makes it. A shared pool thus gives
    /// a later profile the script of an earlier test.
    ///
    /// - Parameters:
    ///   - script: The script that each generation slot plays.
    ///   - recordingsDir: The durable transcripts root, or `nil` (the
    ///     default) to record nothing to disk.
    ///   - standard: The model of the `standard` slot. The default is
    ///     ``standardModel``.
    ///   - flash: The model of the `flash` slot. The default is
    ///     ``flashModel``. Give ``standardModel`` to make a profile whose
    ///     two generation slots share one model.
    /// - Returns: The router and the resolved profile.
    /// - Throws: Whatever `Router.resolve(profile:reporting:)` throws.
    static func make(
        script: ScriptedAgentScript,
        recordingsDir: URL? = nil,
        standard: ModelRef = standardModel,
        flash: ModelRef = flashModel
    ) async throws -> (Router, LanguageModelProfile) {
        let router = Router(
            cacheDir: FileManager.default.temporaryDirectory.appending(path: "ScriptedProfile-\(UUID().uuidString)"),
            recordingsDir: recordingsDir,
            probe: ScriptedMachine(),
            metadataSource: ScriptedMetadata(),
            loader: ScriptedModelLoader(script: script),
            pool: ModelPool())
        let profile = try await router.resolve(
            profile: ProfileDefinition(
                name: "scripted",
                description: "A profile whose models play a script.",
                standard: [standard],
                flash: [flash],
                embedding: [embeddingModel]),
            reporting: ResolutionProgress())
        return (router, profile)
    }
}

/// A loader that downloads nothing and loads scripted containers.
struct ScriptedModelLoader: ModelLoader {
    /// The progress of each load: one byte of one, thus complete.
    private static let completeProgress = DownloadProgress(bytesDownloaded: 1, bytesTotal: 1)

    /// The script that each generation container plays.
    let script: ScriptedAgentScript

    func loadLLM(
        ref: ModelRef,
        slot: ModelSlot,
        context: Int,
        reporting: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws -> any LoadedLLMContainer {
        reporting(Self.completeProgress)
        return ScriptedAgentContainer(model: ScriptedAgentModel(script: script))
    }

    func loadEmbedder(
        ref: ModelRef,
        slot: ModelSlot,
        reporting: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws -> any LoadedEmbeddingContainer {
        reporting(Self.completeProgress)
        return ScriptedEmbeddingContainer()
    }

    func preload(container: any LoadedModelContainer) async throws {}
}

/// An embedding model that gives one constant vector for each text.
struct ScriptedEmbeddingContainer: LoadedEmbeddingContainer {
    /// The length of each vector.
    private static let vectorLength = 8

    /// The value of each component of each vector.
    private static let componentValue: Float = 0.5

    let dimension = ScriptedEmbeddingContainer.vectorLength

    func embed(texts: [String]) async throws -> [[Float]] {
        texts.map { _ in
            [Float](repeating: Self.componentValue, count: Self.vectorLength)
        }
    }
}

/// A machine large enough that the slot fit never fails.
///
/// The sizes are the sizes of the stub machine in FoundationModelsACPAgent.
struct ScriptedMachine: MachineProbe {
    /// The total memory: 64 GiB.
    let totalRAM: Int64 = 64 << 30

    /// The working set that the GPU can use: 48 GiB.
    let recommendedMaxWorkingSetSize: Int64 = 48 << 30

    let chip = "Apple Scripted"
}

/// Metadata of one tiny model, for each repository.
///
/// The numbers are the numbers of the stub metadata in
/// FoundationModelsACPAgent, which are sufficient for the sizing pass.
struct ScriptedMetadata: MetadataSource {
    /// The `config.json` of the tiny model.
    private static let configJSON = """
        {"num_hidden_layers":2,"num_attention_heads":8,\
        "num_key_value_heads":2,"head_dim":16,"hidden_size":128}
        """

    /// The file tree of the tiny model: one 10 MB weights file.
    private static let treeJSON = """
        [{"type":"file","path":"model.safetensors","size":10000000}]
        """

    func fetchRawMetadata(repo: String, revision: String?) async throws -> RawRepoMetadata {
        RawRepoMetadata(configJSON: Data(Self.configJSON.utf8), treeJSON: Data(Self.treeJSON.utf8))
    }
}
