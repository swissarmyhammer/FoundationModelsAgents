import Foundation

/// One coordinated access to a file or a folder (`NSFileCoordinator`).
///
/// A sync engine that presents the item can give the current version before
/// a read, and can see a write or a delete. The coordinated read of
/// `AgentCatalogBuilder` and the coordinated writes and deletes of
/// `AgentWriter` use this one helper. Each caller maps a ``Failure`` to its
/// own error type.
enum FileCoordination {
    /// The kind of a coordinated access, with the options of the coordinator.
    enum Access {
        /// A coordinated read with these options.
        case reading(NSFileCoordinator.ReadingOptions)

        /// A coordinated write (also a delete) with these options.
        case writing(NSFileCoordinator.WritingOptions)
    }

    /// A coordinated access that the file coordinator could not do.
    struct Failure: Error {
        /// The description of the error of the file coordinator.
        let reason: String
    }

    /// The reason of a ``Failure`` when the coordinator gives no error but
    /// does not run the access.
    private static let accessNotRunReason = "the file coordinator did not run the access"

    /// Runs `body` in a coordinated access to the item at `url`.
    ///
    /// When the coordination fails, `body` does not run.
    ///
    /// - Parameters:
    ///   - access: The kind of the access, with the options of the
    ///     coordinator.
    ///   - url: The file or the folder.
    ///   - body: The access. It gets the URL that the coordinator gives.
    /// - Returns: What `body` gave, or the failure of the coordination.
    static func run<Value>(
        _ access: Access, at url: URL, _ body: (URL) -> Value
    ) -> Result<Value, Failure> {
        var value: Value?
        var coordinationError: NSError?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        switch access {
        case .reading(let options):
            coordinator.coordinate(readingItemAt: url, options: options, error: &coordinationError) { value = body($0) }
        case .writing(let options):
            coordinator.coordinate(writingItemAt: url, options: options, error: &coordinationError) { value = body($0) }
        }
        if let coordinationError {
            return .failure(Failure(reason: coordinationError.localizedDescription))
        }
        guard let value else {
            return .failure(Failure(reason: accessNotRunReason))
        }
        return .success(value)
    }
}
