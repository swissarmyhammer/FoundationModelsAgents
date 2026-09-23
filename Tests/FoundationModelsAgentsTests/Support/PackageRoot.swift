import Foundation

/// Finds the root directory of this package for a test that reads a file of
/// the package.
///
/// The root comes from the `#filePath` of this file. Thus a read does not
/// depend on the working directory of the test run.
enum PackageRoot {
    /// The number of path components from the package root to this file:
    /// `Tests`, `FoundationModelsAgentsTests`, `Support`, and
    /// `PackageRoot.swift`.
    private static let depthBelowPackageRoot = 4

    /// The root directory of this package.
    static var directory: URL {
        (0 ..< depthBelowPackageRoot).reduce(URL(fileURLWithPath: #filePath)) { url, _ in
            url.deletingLastPathComponent()
        }
    }
}
