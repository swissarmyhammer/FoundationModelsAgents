import Operations
import OperationsCLI

/// Makes the command line of the agents (plan.md §9.4).
///
/// The command line has four commands, and each has the noun `agent`:
///
/// - `agents agent list [--filter <text>]`
/// - `agents agent start --name <name> --prompt <task>`
/// - `agents agent check [--id <id>]`
/// - `agents agent cancel --id <id>`
///
/// The commands use the same `AgentsToolContext` and the same answer texts
/// as the four operations of the `agents` tool. Two things are different:
///
/// - `agent start` waits for the run and gives the final text. The command
///   has no `ToolContext`, thus the run posts nothing. The run is a
///   host-driven run of ``AgentRunner/start(_:prompt:)``.
/// - `agent list` gives the agent lines only, with no delegation sentence
///   for a model.
///
/// `agent check` and `agent cancel` find only the runs of the runner of the
/// driver. A process that runs one command and then stops has no run to
/// check, thus these two commands are for a host process that stays alive.
///
/// The noun of the tool operation `list agents` is `agents`. The command
/// line uses its own operations, thus each command has the noun `agent`, and
/// the tool operation keeps its name.
///
/// The driver writes nothing to standard output. `OperationCLIDriver.run(arguments:)`
/// gives a `CLIResult` to the host. The output of a command that worked is
/// one JSON string, and the exit code is zero. A corrective, for example an
/// unknown name, and a run that did not finish give the text of the reason
/// and a non-zero exit code.
///
/// ```swift
/// try await registry.load()
/// let runner = AgentRunner(registry: registry, environment: environment)
/// let driver = try AgentsCLI.makeDriver(runner: runner)
/// let result = await driver.run(arguments: Array(CommandLine.arguments.dropFirst()))
/// ```
public enum AgentsCLI {
    /// The name of the command line in its usage, help, and error text.
    public static let executableName = ToolVocabulary.agentsToolName

    /// The description of the command line in its help text.
    static let description = "Start, list, check, and cancel agent runs."

    /// Makes the driver of the four commands over `runner`.
    ///
    /// The commands read the catalog of `runner` at each call, thus the host
    /// calls `AgentRegistry.load()` before the first command.
    ///
    /// - Parameter runner: The runner that owns each run that the commands
    ///   start.
    /// - Returns: The driver.
    /// - Throws: The error of the `OperationTool` init, or of
    ///   `OperationCLIDriver.init(tool:executableName:)`.
    public static func makeDriver(runner: AgentRunner) throws -> OperationCLIDriver {
        let tool = try OperationTool(
            name: executableName,
            description: description,
            context: AgentsToolContext(runner: runner),
            operations: [
                AnyOperation(ListAgentCommand.self),
                AnyOperation(StartAgentCommand.self),
                AnyOperation(CheckAgentCommand.self),
                AnyOperation(CancelAgentCommand.self)
            ]
        )
        return try OperationCLIDriver(tool: tool, executableName: executableName)
    }
}
