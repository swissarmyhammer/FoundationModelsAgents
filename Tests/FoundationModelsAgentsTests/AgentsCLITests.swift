import Foundation
import OperationsCLI
import Testing

@testable import FoundationModelsAgents

/// Pins the command line of the agents (plan.md §9.4): `agents agent list`,
/// `agents agent start`, `agents agent check`, and `agents agent cancel`.
///
/// The tests give the arguments to the driver of `AgentsCLI.makeDriver(runner:)`
/// and read the `CLIResult`. The driver runs over the runner of the fixture
/// library and the scripted profile. A play matches by a key in the prompt of
/// the run.
@Suite("Agents CLI")
struct AgentsCLITests {
    /// A failure that a scripted step throws.
    private enum ScriptedFailure: Error {
        /// The model call of the step failed.
        case broken
    }

    /// The agent of the fixture library that each run starts. It runs on the
    /// `flash` slot.
    private static let reviewer = AgentRunTests.reviewer

    /// The prompt of each run. It is also the key of the play of the run.
    private static let prompt = "cli-run-key: review the diff"

    /// The final text of the play of a run.
    private static let finalText = "The diff is correct."

    /// The model-visible agents of the fixture library, in catalog order.
    private static let visibleAgents = ["code-reviewer", "internal-helper", "lead", "test-writer"]

    /// A name that no agent of the fixture library has.
    private static let unknownName = "no-such-agent"

    /// An id that no run has.
    private static let unknownID = "no-such-run"

    /// A filter that only the description of the project copy of
    /// code-reviewer holds, in a different case.
    private static let qualityFilter = "QUALITY"

    /// The line of the project copy of code-reviewer.
    private static let reviewerLine =
        "- code-reviewer: Reviews code for quality and best practices. This is the project copy."

    /// The start of each agent line: a dash and a space.
    private static let linePrefix = "- "

    /// The exit status of a command that worked.
    private static let successStatus: Int32 = 0

    /// A script with one play for ``prompt``.
    ///
    /// - Parameter steps: The steps of the play.
    /// - Returns: The script.
    private static func script(_ steps: [ScriptedAgentStep]) -> ScriptedAgentScript {
        ScriptedAgentScript([ScriptedAgentPlay(key: prompt, steps: steps)])
    }

    /// Makes the tool harness of the fixture library, and the driver over its
    /// runner.
    ///
    /// - Parameter script: The script that each slot of the profile plays.
    /// - Returns: The harness and the driver. The test deletes the harness.
    /// - Throws: The error of the harness, or of `AgentsCLI.makeDriver(runner:)`.
    private static func makeDriver(
        script: ScriptedAgentScript = ScriptedAgentScript([])
    ) async throws -> (harness: AgentsToolHarness, driver: OperationCLIDriver) {
        let harness = try await AgentsToolHarness.make(script: script)
        do {
            return (harness, try AgentsCLI.makeDriver(runner: harness.runner))
        } catch {
            try? harness.delete()
            throw error
        }
    }

    /// Decodes the output of a command that worked: one JSON string.
    ///
    /// - Parameter result: The result of the driver.
    /// - Returns: The text of the answer.
    /// - Throws: A decode error when the output is not one JSON string.
    private static func text(of result: CLIResult) throws -> String {
        try JSONDecoder().decode(String.self, from: Data(result.output.utf8))
    }

    /// The arguments of `agent start` for the agent `name`.
    ///
    /// - Parameters:
    ///   - name: The name of the agent.
    ///   - prompt: The prompt of the run.
    /// - Returns: The arguments.
    private static func startArguments(_ name: String, prompt: String = prompt) -> [String] {
        ["agent", "start", "--name", name, "--prompt", prompt]
    }

    @Test("agent list gives one - name: description line for each model-visible agent")
    func listGivesOneLineForEachModelVisibleAgent() async throws {
        let (harness, driver) = try await Self.makeDriver()
        defer { try? harness.delete() }

        let result = await driver.run(arguments: ["agent", "list"])
        let lines = try Self.text(of: result).split(separator: "\n")
        let lineNames = lines.map { line in
            String(line.dropFirst(Self.linePrefix.count).prefix { $0 != ":" })
        }

        #expect(result.exitCode == Self.successStatus)
        #expect(lines.allSatisfy { $0.hasPrefix(Self.linePrefix) })
        #expect(lineNames == Self.visibleAgents)
    }

    @Test("agent list with a filter keeps the matches, and the case does not matter")
    func listFilterKeepsMatches() async throws {
        let (harness, driver) = try await Self.makeDriver()
        defer { try? harness.delete() }

        let result = await driver.run(arguments: ["agent", "list", "--filter", Self.qualityFilter])

        #expect(result.exitCode == Self.successStatus)
        #expect(try Self.text(of: result) == Self.reviewerLine)
    }

    @Test("agent start waits for the run and gives the final text", .timeLimit(.minutes(1)))
    func startGivesFinalText() async throws {
        let (harness, driver) = try await Self.makeDriver(script: Self.script([.finalText(Self.finalText)]))
        defer { try? harness.delete() }

        let result = await driver.run(arguments: Self.startArguments(Self.reviewer))
        let run = try #require(await harness.runner.runs(caller: nil).first)

        #expect(result.exitCode == Self.successStatus)
        #expect(try Self.text(of: result) == Self.finalText)
        #expect(run.context == nil)
        #expect(run.depth == AgentRunner.hostDepth)
    }

    @Test("agent start with an unknown name gives the corrective text and a non-zero exit status")
    func startUnknownNameFails() async throws {
        let (harness, driver) = try await Self.makeDriver()
        defer { try? harness.delete() }

        let result = await driver.run(arguments: Self.startArguments(Self.unknownName))

        #expect(result.exitCode != Self.successStatus)
        #expect(result.output.contains(AgentsToolText.unknownAgent(Self.unknownName, available: Self.visibleAgents)))
        #expect(await harness.runner.runs(caller: nil).isEmpty)
    }

    @Test("agent start with a blank prompt gives the corrective text and a non-zero exit status")
    func startBlankPromptFails() async throws {
        let (harness, driver) = try await Self.makeDriver()
        defer { try? harness.delete() }

        let result = await driver.run(arguments: Self.startArguments(Self.reviewer, prompt: " "))

        #expect(result.exitCode != Self.successStatus)
        #expect(result.output.contains(AgentsToolText.blankPrompt))
    }

    @Test("agent start of a run that fails gives the reason and a non-zero exit status")
    func startFailedRunFails() async throws {
        let (harness, driver) = try await Self.makeDriver(script: Self.script([.fail(ScriptedFailure.broken)]))
        defer { try? harness.delete() }

        let result = await driver.run(arguments: Self.startArguments(Self.reviewer))
        let run = try #require(await harness.runner.runs(caller: nil).first)

        #expect(result.exitCode != Self.successStatus)
        #expect(result.output.contains(run.report))
        #expect(run.report.hasPrefix("Agent code-reviewer (\(run.id)) failed: the model failed: "))
    }

    @Test("agent check gives the report of a finished run, and of each run with no id")
    func checkGivesReport() async throws {
        let (harness, driver) = try await Self.makeDriver(script: Self.script([.finalText(Self.finalText)]))
        defer { try? harness.delete() }
        let run = try await harness.runner.start(Self.reviewer, prompt: Self.prompt)
        _ = try await run.result()

        let checked = await driver.run(arguments: ["agent", "check", "--id", run.id.description])
        let all = await driver.run(arguments: ["agent", "check"])
        let report = "Agent code-reviewer (\(run.id)) finished.\n\n\(Self.finalText)"

        #expect(checked.exitCode == Self.successStatus)
        #expect(try Self.text(of: checked) == report)
        #expect(all.exitCode == Self.successStatus)
        #expect(try Self.text(of: all) == report)
    }

    @Test("agent check and agent cancel with an unknown id give the corrective text and a non-zero exit status")
    func unknownIDFails() async throws {
        let (harness, driver) = try await Self.makeDriver()
        defer { try? harness.delete() }
        let corrective = AgentsToolText.unknownRun(Self.unknownID, ids: [])

        let checked = await driver.run(arguments: ["agent", "check", "--id", Self.unknownID])
        let cancelled = await driver.run(arguments: ["agent", "cancel", "--id", Self.unknownID])

        #expect(checked.exitCode != Self.successStatus)
        #expect(checked.output.contains(corrective))
        #expect(cancelled.exitCode != Self.successStatus)
        #expect(cancelled.output.contains(corrective))
    }

    @Test("agent cancel cancels a run in operation", .timeLimit(.minutes(1)))
    func cancelCancelsRun() async throws {
        let gate = ScriptedGate()
        let (harness, driver) = try await Self.makeDriver(
            script: Self.script([.wait(gate), .finalText(Self.finalText)]))
        defer { try? harness.delete() }
        let run = try await harness.runner.start(Self.reviewer, prompt: Self.prompt)
        await gate.waitForArrival()

        let result = await driver.run(arguments: ["agent", "cancel", "--id", run.id.description])

        #expect(result.exitCode == Self.successStatus)
        #expect(try Self.text(of: result).hasPrefix("The cancel of \(run.subject) was sent"))
        #expect(await run.finalState() == .cancelled)
    }

    @Test("the noun of the command line is agent; agents is not a command")
    func nounIsAgent() async throws {
        let (harness, driver) = try await Self.makeDriver()
        defer { try? harness.delete() }

        let result = await driver.run(arguments: ["agents", "list"])

        #expect(result.exitCode != Self.successStatus)
    }
}
