import Foundation
import FoundationModelsAgents
import FoundationModelsRouter
import FoundationModelsRouterTestSupport
import FoundationModelsSkills
import HuggingFace
import MLXHuggingFace
import MLXLMCommon
import Testing
import Tokenizers

/// The resolved real profile of the live suites (plan.md §15).
///
/// The profile has small `mlx-community` models: a different model in the
/// `standard` slot and in the `flash` slot, and an embedding model. Thus each
/// generation slot has its own generation gate. The recipe is the recipe of
/// `Examples/agents-demo/AgentsDemoProfile.swift`: a `Router` over the live
/// model loader, then one resolve of ``definition``.
///
/// The process resolves the profile one time, in ``shared``. Each live test
/// awaits that value, thus the models load one time for the whole run. The
/// resolve reads `MetalLibraryTestBootstrap.ensureColocatedMetallib` first:
/// under a plain `swift test`, mlx-swift cannot find its shader library
/// without it.
///
/// The router records each session under ``recordingsDirectory``, in the
/// `.build/` folder of this package. The CI input
/// `integration-artifacts-path` uploads that folder.
struct LiveProfile: Sendable {
    /// The number of path components from the root of this package to this
    /// file: `Tests`, `AgentsIntegrationTests`, `Support`, and
    /// `LiveProfile.swift`.
    private static let depthBelowPackageRoot = 4

    /// The path of the recordings folder, relative to the root of this
    /// package.
    private static let recordingsRelativePath = ".build/recordings"

    /// The number of minutes that one live test can use. The first live test
    /// also waits for the models to load.
    private static let testMinutes = 15

    /// The time limit of each live test.
    static let timeLimit: TimeLimitTrait.Duration = .minutes(testMinutes)

    /// The profile that the live suites resolve.
    static let definition = ProfileDefinition(
        name: "agents-integration",
        description: "Small local models for the FoundationModelsAgents integration suites.",
        standard: ["mlx-community/Qwen3-4B-4bit"],
        flash: ["mlx-community/Qwen3-1.7B-4bit"],
        embedding: ["mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ"])

    /// The one resolve of the process.
    ///
    /// The first `await` of ``shared`` waits for the models to load. Each
    /// later `await` gets the same value at once.
    static let shared = Task { try await resolve() }

    /// The router of ``profile``. The value keeps it, because the resident
    /// models of the profile belong to the pool of this router.
    let router: Router

    /// The resolved, resident profile.
    let profile: LanguageModelProfile

    /// The root folder of this package.
    static var packageDirectory: URL {
        (0 ..< depthBelowPackageRoot).reduce(URL(fileURLWithPath: #filePath)) { url, _ in
            url.deletingLastPathComponent()
        }
    }

    /// The recordings root of the router: `IntegrationTests/.build/recordings`.
    static var recordingsDirectory: URL {
        packageDirectory.appendingPathComponent(recordingsRelativePath, isDirectory: true)
    }

    /// Makes a runner over the live profile.
    ///
    /// The environment has no skills layer and the default limits of
    /// `AgentEnvironment`.
    ///
    /// - Parameters:
    ///   - registry: The registry of the agents. The caller loads it.
    ///   - workingDirectory: The working directory of each run.
    /// - Returns: The runner. The caller stops it at the end of the test.
    func makeRunner(registry: AgentRegistry, workingDirectory: URL) -> AgentRunner {
        let environment = AgentEnvironment(
            profile: profile, skills: SkillsRegistry(roots: []), workingDirectory: workingDirectory)
        return AgentRunner(registry: registry, environment: environment)
    }

    /// Installs the metallib link, makes a router over the live model loader,
    /// and resolves ``definition``.
    ///
    /// The first resolve on a host downloads the models from Hugging Face.
    ///
    /// - Returns: The router and the resolved profile.
    /// - Throws: The error of `Router.resolve(profile:reporting:)`.
    private static func resolve() async throws -> LiveProfile {
        _ = MetalLibraryTestBootstrap.ensureColocatedMetallib
        let router = Router(
            recordingsDir: recordingsDirectory,
            loader: LiveModelLoader(
                downloader: #hubDownloader(),
                tokenizerLoader: #huggingFaceTokenizerLoader()))
        let profile = try await router.resolve(profile: definition, reporting: ResolutionProgress())
        return LiveProfile(router: router, profile: profile)
    }
}
