/// Builds the description of the `agents` tool (plan.md §9.1).
///
/// A model reads the description of a tool before it plans, thus the
/// description is where the model learns which agents it can start. The
/// text has the fixed sentences, which tell the model how to delegate, and
/// then the list of the agents.
///
/// The list has a character limit. The limit counts the list only, thus the
/// fixed sentences take no room from it and are never cut. The builder tries
/// four forms in order and uses the first one that fits the limit:
///
/// 1. One `- name: description` line for each agent.
/// 2. The same lines, with each description cut to 200 characters.
/// 3. The names only, on one comma-separated line.
/// 4. As many names as fit, then a line with the count of the names that are
///    not listed and the tip to see them with `list agents`.
///
/// An empty catalog gives the no-agents line in place of the list.
enum AgentsToolDescription {
    /// One agent of the list: its name and its description.
    struct Entry: Sendable {
        /// The name of the agent.
        let name: String

        /// The description of the agent, or `nil` when it has none.
        let description: String?
    }

    /// The delegation sentence: how to give a task to an agent. The fixed
    /// sentences hold it, and the answer of `list agents` ends with it.
    static let delegationSentence = """
        To give a task to an agent, call this tool with {"op": "start agent", "name": "<name>", \
        "prompt": "<the full task>"}.
        """

    /// The fixed sentences: what an agent is and how to delegate to one.
    private static let fixedSentences = """
        An agent is a model session that works in the background. Each agent starts with an empty context \
        and sees only the prompt that you give it, so put all that the agent needs in the prompt. \
        \(delegationSentence) The call returns at once. When the agent finishes, its final \
        message comes to you as a tool result. Your answer is the text of your last turn, so give your \
        final answer after you have the results of the agents that you started. You can ask about a run \
        with {"op": "check agent", "id": "<id>"}.
        """

    /// The line that replaces the list when no agent is visible.
    private static let noAgentsLine = "No agents are installed now."

    /// The words after the count on the last line of form 4.
    private static let notListedNote = "more agents are not listed. See them with `list agents`."

    /// The most characters that a description of form 2 has, with the
    /// ellipsis.
    private static let cutDescriptionLength = 200

    /// The character at the end of a cut description.
    private static let ellipsis = "…"

    /// The text between the fixed sentences and the list.
    private static let listSeparator = "\n\n"

    /// The text between two lines of the list.
    private static let lineBreak = "\n"

    /// The text between two names of forms 3 and 4.
    private static let nameSeparator = ", "

    /// Builds the description for `agents`.
    ///
    /// - Parameters:
    ///   - agents: The agents that the tool can start, in list order.
    ///   - characterLimit: The most characters that the list can have. The
    ///     fixed sentences do not count against it.
    /// - Returns: The fixed sentences, then the list, or the no-agents line
    ///   for an empty `agents`.
    static func make(agents: [Entry], characterLimit: Int) -> String {
        let list = agents.isEmpty ? noAgentsLine : list(for: agents, characterLimit: characterLimit)
        return fixedSentences + listSeparator + list
    }

    /// Gives one `- name: description` line for each agent, each description
    /// on one line and not cut. The answer of `list agents` uses these lines.
    ///
    /// - Parameter agents: The agents, in list order.
    /// - Returns: The lines, joined with line breaks.
    static func lines(for agents: [Entry]) -> String {
        describedList(oneLineEntries(agents))
    }

    /// Puts the description of each agent on one line.
    ///
    /// - Parameter agents: The agents, in list order.
    /// - Returns: The same agents, each description on one line.
    private static func oneLineEntries(_ agents: [Entry]) -> [Entry] {
        agents.map { Entry(name: $0.name, description: $0.description.map(oneLine)) }
    }

    /// Gives the list of the first form that fits `characterLimit`.
    ///
    /// - Parameters:
    ///   - agents: The agents of the list. It is not empty.
    ///   - characterLimit: The most characters that the list can have.
    /// - Returns: The list.
    private static func list(for agents: [Entry], characterLimit: Int) -> String {
        let oneLineAgents = oneLineEntries(agents)
        let names = agents.map(\.name)
        let fullList = describedList(oneLineAgents)
        let cutList = describedList(oneLineAgents.map { Entry(name: $0.name, description: $0.description.map(cut)) })
        let nameLine = names.joined(separator: nameSeparator)
        let fitting = [fullList, cutList, nameLine].first { $0.count <= characterLimit }
        return fitting ?? partialNameList(names, characterLimit: characterLimit)
    }

    /// Gives one line for each agent: `- name: description`, or `- name`
    /// when the agent has no description.
    ///
    /// - Parameter agents: The agents, each description on one line.
    /// - Returns: The lines, joined with line breaks.
    private static func describedList(_ agents: [Entry]) -> String {
        agents.lazy.map { agent in
            agent.description.map { "- \(agent.name): \($0)" } ?? "- \(agent.name)"
        }.joined(separator: lineBreak)
    }

    /// Puts `text` on one line: each run of white space becomes one space.
    ///
    /// - Parameter text: A description.
    /// - Returns: The description on one line, with no white space at the
    ///   start or the end.
    private static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Cuts `text` to `cutDescriptionLength` characters.
    ///
    /// - Parameter text: A description on one line.
    /// - Returns: `text` when it fits, otherwise its first characters and the
    ///   ellipsis, `cutDescriptionLength` characters in all.
    private static func cut(_ text: String) -> String {
        guard text.count > cutDescriptionLength else {
            return text
        }
        return text.prefix(cutDescriptionLength - ellipsis.count) + ellipsis
    }

    /// Gives as many names as fit `characterLimit` on one line, then the line
    /// that counts the names that are not listed.
    ///
    /// The count line always shows, thus the model always learns that the
    /// list is not complete. When no name fits beside it, the count line is
    /// the whole list.
    ///
    /// - Parameters:
    ///   - names: Each name, in list order.
    ///   - characterLimit: The most characters that the list can have.
    /// - Returns: The names that fit and the count line.
    private static func partialNameList(_ names: [String], characterLimit: Int) -> String {
        let shownCount = names.indices.prefix { index in
            partialList(names, shownCount: index + 1).count <= characterLimit
        }.count
        return partialList(names, shownCount: shownCount)
    }

    /// Gives the first `shownCount` names on one line, then the line that
    /// counts the other names.
    ///
    /// - Parameters:
    ///   - names: Each name, in list order.
    ///   - shownCount: The number of names to show.
    /// - Returns: The name line and the count line, or the count line only
    ///   when `shownCount` is zero.
    private static func partialList(_ names: [String], shownCount: Int) -> String {
        let countLine = notListedLine(count: names.count - shownCount)
        guard shownCount > 0 else {
            return countLine
        }
        return names.prefix(shownCount).joined(separator: nameSeparator) + lineBreak + countLine
    }

    /// Gives the line that counts the names that are not listed.
    ///
    /// - Parameter count: The number of names that are not listed.
    /// - Returns: The count line.
    private static func notListedLine(count: Int) -> String {
        "\(count) \(notListedNote)"
    }
}
