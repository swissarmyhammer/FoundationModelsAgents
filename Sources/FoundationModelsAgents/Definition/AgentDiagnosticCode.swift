extension AgentDiagnostic {
    /// What a diagnostic is about, as a fixed code.
    ///
    /// The message of a diagnostic is text for a person, and it can change. A
    /// client keys on the code: the manager view of the agents (APP-12) reads
    /// it from the `agents` GraphQL endpoint (``AgentsGraph``). The raw value
    /// is the code in `UPPER_SNAKE`, qualifier first (EXTRAS-9 rule 8). A new
    /// finding gets a new case; the raw value of a case does not change.
    public enum Code: String, Sendable, Equatable, CaseIterable {
        // MARK: The load of a file

        /// The name of an agent folder is not a valid id. The file is skipped.
        case invalidID = "INVALID_ID"

        /// The file has no frontmatter block, or its frontmatter did not
        /// decode. The file is skipped.
        case noFrontmatter = "NO_FRONTMATTER"

        /// The frontmatter did not decode on the first read, and the reader
        /// tells why.
        case decodeFailure = "DECODE_FAILURE"

        /// A `.md` file directly in `agents/` has the old format, and gives no
        /// agent.
        case oldFormat = "OLD_FORMAT"

        /// The agent document is a placeholder of a sync engine, or the build
        /// cannot read it as text yet. The agent is skipped until the file is
        /// local.
        case notLocal = "NOT_LOCAL"

        /// The coordinated read of the agent document failed. The agent is
        /// skipped.
        case failedRead = "FAILED_READ"

        /// The winning copy has `enabled: false`. The agent is off.
        case disabledAgent = "DISABLED_AGENT"

        /// The `enabled` value of the winning copy is not `true` or `false`.
        /// The agent is off.
        case invalidEnabled = "INVALID_ENABLED"

        // MARK: The layers

        /// A higher layer holds a copy of the same agent, and hides the copy
        /// of this layer.
        case hiddenCopy = "HIDDEN_COPY"

        /// A `default/` agent folder is beside the root `AGENT.md` of one
        /// layer. The root `AGENT.md` is the default agent.
        case duplicateDefault = "DUPLICATE_DEFAULT"

        // MARK: The frontmatter

        /// The frontmatter has no `name`. The folder name is the id.
        case missingName = "MISSING_NAME"

        /// The `name` value is not the folder name. The folder name is the id.
        case mismatchedName = "MISMATCHED_NAME"

        /// The frontmatter has no `description`. The model cannot see the
        /// agent.
        case missingDescription = "MISSING_DESCRIPTION"

        /// The `description` is longer than the limit.
        case longDescription = "LONG_DESCRIPTION"

        /// The `model` value is empty. A run uses the default slot.
        case emptyModel = "EMPTY_MODEL"

        /// A value of `disallowedTools`, `tools` or `maxTurns` is not correct.
        /// The agent gets less access.
        case invalidAccessKey = "INVALID_ACCESS_KEY"

        /// A key that this package does not support. The key is ignored.
        case unsupportedKey = "UNSUPPORTED_KEY"

        /// A key that this package does not know. The key is kept as data.
        case unknownKey = "UNKNOWN_KEY"

        /// `background: false` is ignored: each run is a background run.
        case ignoredBackground = "IGNORED_BACKGROUND"

        /// The value of a key has the wrong type.
        case wrongType = "WRONG_TYPE"

        /// A note of the decode of the frontmatter, for example a value that
        /// the colon retry read.
        case decodeNote = "DECODE_NOTE"

        // MARK: The environment of a runner

        /// The `model` value matches no slot of the profile.
        case unmatchedModel = "UNMATCHED_MODEL"

        /// An entry of `tools` or `disallowedTools` matches no tool.
        case unknownTool = "UNKNOWN_TOOL"

        /// An `Agent` entry of `tools` at the depth limit: the run gets no
        /// `agents` tool to start runs.
        case agentEntryAtMaxDepth = "AGENT_ENTRY_AT_MAX_DEPTH"

        /// A `skills` entry names no skill of the skills registry.
        case unknownSkill = "UNKNOWN_SKILL"

        /// A `skills` entry names a skill that the model cannot see.
        case hiddenSkill = "HIDDEN_SKILL"
    }
}
