import Foundation
import Testing

/// Pins `.github/workflows/ci.yml` to the shared CI shape of the organization.
///
/// The shape is one job that delegates to the shared `swift-ci.yaml` workflow.
/// This suite pins four properties of that shape:
///
/// - The `uses:` line names the shared workflow at `@main`.
/// - Exactly one job exists, and it has no `steps:` key. Thus the shared
///   workflow does every test run.
/// - The triggers are a push to `main`, a pull request, and a manual dispatch.
/// - The concurrency group changes with the ref, and a new run of the same ref
///   cancels the run before it.
///
/// An edit that points `uses:` to a different workflow, adds a local job that
/// runs steps, or removes a trigger makes this suite fail.
@Suite("CI workflow")
struct CIWorkflowTests {
    /// The full `uses:` line that `ci.yml` must hold. The ref is `@main`,
    /// which each package of the family follows.
    private static let sharedWorkflowReference =
        "uses: swissarmyhammer/workflows/.github/workflows/swift-ci.yaml@main"

    /// The number of jobs that `ci.yml` can declare. One job keeps each test
    /// run in the shared workflow.
    private static let allowedJobCount = 1

    /// The path of the workflow file, relative to the package root.
    private static let workflowRelativePath = ".github/workflows/ci.yml"

    /// The number of path components from the package root to this file:
    /// `Tests`, `FoundationModelsAgentsTests`, and `CIWorkflowTests.swift`.
    private static let depthBelowPackageRoot = 3

    /// The lines that the `on:` block must hold, with their indentation.
    ///
    /// The indentation is part of each line. It makes `branches: [main]` a
    /// child of `push:`, not a child of the `on:` block.
    private static let expectedTriggerLines = [
        "  push:",
        "    branches: [main]",
        "  pull_request:",
        "  workflow_dispatch:"
    ]

    @Test("ci.yml calls the shared swift-ci.yaml workflow at @main")
    func callsTheSharedWorkflow() throws {
        let lines = try Self.workflowLines()
        let callsShared = lines.contains { line in
            line.trimmingCharacters(in: .whitespaces) == Self.sharedWorkflowReference
        }
        #expect(callsShared, "ci.yml must hold \"\(Self.sharedWorkflowReference)\".")
    }

    @Test("ci.yml declares exactly one job, and that job delegates instead of running steps")
    func declaresOneDelegatingJob() throws {
        let jobs = Self.block(under: "jobs:", in: try Self.workflowLines())

        // A job key has an indentation of two spaces, for example "  ci:".
        // Only the lines below "jobs:" are read, because the children of
        // "on:" have the same shape.
        let jobKeyPattern = try Regex(#"^  [a-zA-Z0-9_-]+:$"#)
        let jobKeys = jobs.filter { $0.wholeMatch(of: jobKeyPattern) != nil }
        #expect(
            jobKeys.count == Self.allowedJobCount,
            """
            ci.yml must declare exactly \(Self.allowedJobCount) job, which delegates to the shared \
            workflow; found job keys: \(jobKeys)
            """
        )

        // A "steps:" key shows a local job that runs its own commands. A job
        // that delegates has no such key.
        let stepKeys = jobs.filter { $0.trimmingCharacters(in: .whitespaces) == "steps:" }
        #expect(
            stepKeys.isEmpty,
            """
            ci.yml must declare no "steps:" key. The shared workflow does each test run; \
            found \(stepKeys.count) such keys.
            """
        )
    }

    @Test("ci.yml runs on a push to main, on a pull request, and on a manual dispatch")
    func declaresTheExpectedTriggers() throws {
        let triggers = Self.block(under: "on:", in: try Self.workflowLines())
        for expected in Self.expectedTriggerLines {
            #expect(
                triggers.contains(Substring(expected)),
                "ci.yml must declare the line \"\(expected)\" in its \"on:\" block; found: \(triggers)"
            )
        }
    }

    @Test("ci.yml cancels a run when a newer run of the same ref starts")
    func declaresConcurrencyThatCancelsInProgress() throws {
        let concurrency = Self.block(under: "concurrency:", in: try Self.workflowLines())
        let trimmed = concurrency.map { $0.trimmingCharacters(in: .whitespaces) }

        // The group must change with the ref. A constant group cancels runs
        // of unrelated branches.
        #expect(
            trimmed.contains("group: ci-${{ github.ref }}"),
            "ci.yml must set the concurrency group \"ci-${{ github.ref }}\"; found: \(concurrency)"
        )
        #expect(
            trimmed.contains("cancel-in-progress: true"),
            "ci.yml must set \"cancel-in-progress: true\" in its \"concurrency\" block; found: \(concurrency)"
        )
    }

    /// Reads the workflow file from the package root.
    ///
    /// The package root is found from the `#filePath` of this file. Thus the
    /// read does not depend on the working directory of the test run.
    ///
    /// - Returns: Each line of the workflow file.
    /// - Throws: An error when the file cannot be read.
    private static func workflowLines() throws -> [Substring] {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< depthBelowPackageRoot {
            root.deleteLastPathComponent()
        }
        let url = root.appendingPathComponent(workflowRelativePath)
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
    }

    /// The lines below the top-level `key` of a workflow file.
    ///
    /// The block starts at the line after `key`. It stops at the next line
    /// that has content in column one, which is the next top-level key. An
    /// empty line does not stop the block.
    ///
    /// - Parameters:
    ///   - key: A top-level key with its colon, for example `"jobs:"`.
    ///   - lines: The lines of the workflow file.
    /// - Returns: The lines below `key`, or an empty array when `key` is not
    ///   in the file.
    private static func block(under key: String, in lines: [Substring]) -> [Substring] {
        let keyIndex = lines.firstIndex(of: Substring(key)) ?? lines.endIndex
        let below = lines[keyIndex...].dropFirst()
        return Array(below.prefix { $0.isEmpty || $0.hasPrefix(" ") })
    }
}
