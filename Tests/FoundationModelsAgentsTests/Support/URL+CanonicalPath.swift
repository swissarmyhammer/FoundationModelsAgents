import Foundation

extension URL {
    /// The path of this URL after the standardize step and the resolve of
    /// each symbolic link, with no trailing slash.
    ///
    /// Use it to compare two file URLs. Thus `/var/folders` and
    /// `/private/var/folders` compare equal, and a `.` or `..` component does
    /// not change the result.
    var canonicalPath: String {
        standardizedFileURL.resolvingSymlinksInPath().path
    }
}
