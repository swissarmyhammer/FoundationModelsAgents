import Foundation
import FoundationModelsExtras

/// Gives the URLs of the fixture layers at `Examples/agent-library`
/// (plan.md §13), and the local layer stack over them.
///
/// Each URL comes from `PackageRoot.directory`. Thus the helper never reads
/// the real home directory or `$XDG_CONFIG_HOME`, and the tests stay
/// hermetic.
enum FixtureLibrary {
    /// The dotfolder name of the stack. The project layer is
    /// `project/.agents/`.
    static let dotfolderName = "agents"

    /// The agent ids of the combined view of the three local layers.
    static let localAgentIDs: Set = [
        "code-reviewer",
        "test-writer",
        "lead",
        "internal-helper",
        "release-manager"
    ]

    /// The root of the fixture library: `Examples/agent-library`.
    static var root: URL {
        PackageRoot.directory
            .appendingPathComponent("Examples", isDirectory: true)
            .appendingPathComponent("agent-library", isDirectory: true)
    }

    /// The root of the `defaults` layer: `defaults/`.
    static var defaultsDirectory: URL {
        root.appendingPathComponent("defaults", isDirectory: true)
    }

    /// The root of the `user` layer: `user/`.
    static var userDirectory: URL {
        root.appendingPathComponent("user", isDirectory: true)
    }

    /// The working directory of the project: `project/`. The project layer
    /// is its `.agents/` dotfolder.
    static var projectWorkingDirectory: URL {
        root.appendingPathComponent("project", isDirectory: true)
    }

    /// The root of the `project` layer: `project/.agents/`.
    static var projectDirectory: URL {
        projectWorkingDirectory.appendingPathComponent(".\(dotfolderName)", isDirectory: true)
    }

    /// The source root of the fixture marketplace: `marketplace/`. It holds
    /// `.claude-plugin/marketplace.json` and the `plugins/` folder.
    static var marketplaceDirectory: URL {
        root.appendingPathComponent("marketplace", isDirectory: true)
    }

    /// The folder of the broken agent fixtures: `broken/agents/`. Each file
    /// in it holds one defect.
    static var brokenAgentsDirectory: URL {
        root.appendingPathComponent("broken", isDirectory: true)
            .appendingPathComponent("agents", isDirectory: true)
    }

    /// The local layer stack over the fixture library:
    /// `defaults < user < project`.
    ///
    /// The environment is empty. Thus `AGENTS_DEFAULTS_DIR` and
    /// `XDG_CONFIG_HOME` cannot move a layer onto a real host directory.
    ///
    /// - Returns: The stack, lowest layer first.
    static func stack() -> DotfolderStack {
        DotfolderStack(
            name: dotfolderName,
            workingDirectory: projectWorkingDirectory,
            defaultsDirectory: defaultsDirectory,
            userDirectory: userDirectory,
            environment: [:])
    }

    /// Resolves `relativePath`, for example `"defaults/agents/lead.md"`,
    /// against `root`.
    ///
    /// The path must be relative. It must not start with `/` or `~`, and it
    /// must not hold a `..` component. Thus each URL stays under `root`.
    ///
    /// - Parameter relativePath: A path relative to `Examples/agent-library`.
    /// - Returns: The URL of the fixture.
    static func url(_ relativePath: String) -> URL {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: true)
        precondition(
            !relativePath.hasPrefix("/") && !relativePath.hasPrefix("~")
                && !components.contains(".."),
            "FixtureLibrary: the path must be relative with no \"..\"; got \"\(relativePath)\"")
        return root.appendingPathComponent(relativePath)
    }
}
