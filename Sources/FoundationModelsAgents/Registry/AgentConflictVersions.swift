import Foundation

/// One unresolved conflict version of an agent file: a version that a sync
/// service kept from a different device.
///
/// The `agents` endpoint gives the versions of each agent as
/// `Agent.conflicts`. Thus each client of the endpoint, also a client on a
/// different device, sees that an agent has a conflict (D154 rule 1).
public struct AgentConflictVersion: Sendable, Hashable {
    /// The id of the version. ``FileVersionConflictSource`` gives the
    /// archived `persistentIdentifier` of the `NSFileVersion`, in base64.
    /// Thus a host finds the version again with
    /// `NSFileVersion(itemAt:forPersistentIdentifier:)`.
    public let id: String

    /// The name of the device that saved the version, or `nil` when the
    /// source does not know it.
    public let deviceName: String?

    /// The time of the last change of the version, or `nil` when the source
    /// does not know it.
    public let modificationDate: Date?

    /// Makes a conflict version.
    ///
    /// - Parameters:
    ///   - id: The id of the version.
    ///   - deviceName: The name of the device that saved the version.
    ///   - modificationDate: The time of the last change of the version.
    public init(id: String, deviceName: String?, modificationDate: Date?) {
        self.id = id
        self.deviceName = deviceName
        self.modificationDate = modificationDate
    }
}

/// The source of the conflict versions of the agent files of an
/// ``AgentRegistry``.
///
/// Each build of the registry calls ``conflictVersions(of:)`` for the file of
/// each agent of a local layer. A registry with `watch: true` also follows
/// ``changes(under:)`` for its watched roots, and each value gives a reload.
/// Thus a new conflict version or a resolve changes the catalog, and the
/// `agents` endpoint sends a change with the id of the agent in `changed`.
public protocol AgentConflictVersionSource: Sendable {
    /// Gives the unresolved conflict versions of one file.
    ///
    /// - Parameter url: The URL of the agent file.
    /// - Returns: The versions, or an empty list when the file has none.
    func conflictVersions(of url: URL) -> [AgentConflictVersion]

    /// Gives a value each time a conflict version comes or is resolved for a
    /// file under one of the roots.
    ///
    /// The registry cancels its iteration of the stream when it stops to
    /// watch, thus the source stops to follow the roots when the stream
    /// terminates.
    ///
    /// - Parameter roots: The roots to follow.
    /// - Returns: The stream of the changes.
    func changes(under roots: [URL]) -> AsyncStream<Void>
}

/// The conflict versions of `NSFileVersion`: the versions that a sync service
/// keeps for a file that two devices changed.
///
/// The change signal comes from one `NSFilePresenter` for each root. The
/// presenter gets `presentedSubitem(at:didGain:)`,
/// `presentedSubitem(at:didLose:)` and
/// `presentedSubitem(at:didResolveConflict:)` for each file under the root.
public struct FileVersionConflictSource: AgentConflictVersionSource {
    /// Makes the source.
    public init() {}

    /// Gives the unresolved conflict versions of one file from
    /// `NSFileVersion`.
    ///
    /// - Parameter url: The URL of the agent file.
    /// - Returns: The versions, or an empty list when the file has none or
    ///   is not in a synced folder.
    public func conflictVersions(of url: URL) -> [AgentConflictVersion] {
        (NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []).map { version in
            AgentConflictVersion(
                id: Self.id(of: version), deviceName: version.localizedNameOfSavingComputer,
                modificationDate: version.modificationDate)
        }
    }

    /// Follows the conflict versions under each root with one file
    /// presenter for each root.
    ///
    /// - Parameter roots: The roots to follow.
    /// - Returns: The stream of the changes. Its termination removes the
    ///   presenters.
    public func changes(under roots: [URL]) -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let presenters = roots.map { root in
                ConflictVersionPresenter(root: root) { continuation.yield() }
            }
            presenters.forEach(NSFileCoordinator.addFilePresenter)
            continuation.onTermination = { _ in
                presenters.forEach(NSFileCoordinator.removeFilePresenter)
            }
        }
    }

    /// Gives the id of a version: the archived `persistentIdentifier` in
    /// base64, or the path of the version when the archive fails.
    ///
    /// - Parameter version: The version.
    /// - Returns: The id.
    private static func id(of version: NSFileVersion) -> String {
        let archived = try? NSKeyedArchiver.archivedData(
            withRootObject: version.persistentIdentifier, requiringSecureCoding: true)
        return archived?.base64EncodedString() ?? version.url.path
    }
}

/// The file presenter of one root of ``FileVersionConflictSource``.
///
/// Each stored property is immutable after the init, and the handler is
/// `Sendable`, thus the presenter is safe on the queue of the presenter and
/// in the termination handler of the stream.
private final class ConflictVersionPresenter: NSObject, NSFilePresenter, @unchecked Sendable {
    /// The root that the presenter follows.
    let presentedItemURL: URL?

    /// The queue of the calls of the presenter.
    let presentedItemOperationQueue: OperationQueue

    /// Called for each change of a conflict version under the root.
    private let onChange: @Sendable () -> Void

    /// Makes a presenter of one root.
    ///
    /// - Parameters:
    ///   - root: The root.
    ///   - onChange: Called for each change of a conflict version.
    init(root: URL, onChange: @escaping @Sendable () -> Void) {
        presentedItemURL = root
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        presentedItemOperationQueue = queue
        self.onChange = onChange
    }

    /// A file under the root got a version.
    func presentedSubitem(at url: URL, didGain version: NSFileVersion) {
        onChange()
    }

    /// A file under the root lost a version.
    func presentedSubitem(at url: URL, didLose version: NSFileVersion) {
        onChange()
    }

    /// A conflict version of a file under the root was resolved.
    func presentedSubitem(at url: URL, didResolveConflict version: NSFileVersion) {
        onChange()
    }
}
