import FoundationModelsSkills

/// The `skills:` preload of an agent.
///
/// At run start, the run appends the rendered body of each skill of the
/// `skills` key to its instructions, after the body of the agent, in the
/// order of the key. `SkillsRegistry.call(id:)` renders each body.
///
/// Only a skill that the `skills` tool shows can load: the preload uses the
/// visibility rule of that tool (``AgentEnvironment/skillsVisibility``). A
/// name that no skill of the registry has, and a skill that the rule hides
/// (by default, a skill with `disable-model-invocation: true`), is a warning
/// and is skipped. `runner.catalog()` gives these warnings. The preload does
/// not add the `skills` tool: the environment puts that tool in its
/// `ToolCatalog`.
struct AgentSkillsPreload: Sendable {
    /// The names of the `skills` key that the run loads, and a finding for
    /// each name that the run skips.
    struct Selection: Sendable {
        /// The names to load, in the order of the key.
        let loaded: [String]

        /// One warning for each skipped name, in the order of the key.
        let findings: [AgentFinding]
    }

    /// The render of one skill: the body, `nil` when the registry no longer
    /// has the skill, or the failure of the render.
    typealias Render = Result<String?, AgentRunFailure>

    /// The skills registry that gives the skills.
    let skills: SkillsRegistry

    /// Tells if the `skills` tool shows a skill. The preload skips each
    /// skill that this rule hides.
    let isVisible: AgentEnvironment.SkillsVisibility

    /// The warning for a name that no skill of the registry has.
    ///
    /// - Parameter name: The entry of the `skills` key.
    /// - Returns: The finding.
    static func unknownSkillFinding(_ name: String) -> AgentFinding {
        AgentFinding(
            severity: .warning,
            message: "the 'skills' entry '\(name)' matches no skill of the skills registry; the entry is skipped")
    }

    /// The warning for a skill that the `skills` tool hides.
    ///
    /// - Parameter name: The entry of the `skills` key.
    /// - Returns: The finding.
    static func hiddenSkillFinding(_ name: String) -> AgentFinding {
        AgentFinding(
            severity: .warning,
            message: "the 'skills' entry '\(name)' names a skill that is not model-visible; the entry is skipped")
    }

    /// Sorts the entries of a `skills` key into the names to load and the
    /// warnings of the skipped names.
    ///
    /// - Parameter names: The entries of the `skills` key.
    /// - Returns: The selection.
    func selection(of names: [String]) -> Selection {
        let visibility = Dictionary(
            skills.metadata().lazy.map { metadata in (metadata.id, isVisible(metadata)) },
            uniquingKeysWith: { _, last in last })
        return Selection(
            loaded: names.filter { name in visibility[name] == true },
            findings: names.compactMap { name in Self.finding(for: name, isModelVisible: visibility[name]) })
    }

    /// Gives the warnings of the `skills` key of one agent, and renders no
    /// skill.
    ///
    /// - Parameter definition: The agent.
    /// - Returns: One warning for each skipped name, in the order of the key.
    func diagnostics(of definition: AgentDefinition) -> [AgentDiagnostic] {
        selection(of: definition.skills).findings.map { finding in
            finding.diagnostic(agent: definition.id, provenance: definition.provenance)
        }
    }

    /// Renders the body of each skill of the `skills` key that can load.
    ///
    /// The bodies render at the same time, and come back in the order of the
    /// key. A skill that the registry removes after the selection is
    /// skipped, as an unknown name is.
    ///
    /// - Parameter definition: The agent.
    /// - Returns: The rendered bodies, in the order of the key.
    /// - Throws: ``AgentRunFailure/skillRenderFailed(skill:description:)``
    ///   when the render of a skill fails.
    func bodies(of definition: AgentDefinition) async throws(AgentRunFailure) -> [String] {
        let loaded = selection(of: definition.skills).loaded
        let skills = skills
        let renders = await withTaskGroup(of: (index: Int, render: Render).self) { group in
            for (index, name) in loaded.enumerated() {
                group.addTask { (index, await Self.render(name, in: skills)) }
            }
            return await group.reduce(into: [Int: Render]()) { renders, next in
                renders[next.index] = next.render
            }
        }
        return try loaded.indices.map { index throws(AgentRunFailure) in
            try renders[index]?.get() ?? nil
        }.compactMap(\.self)
    }

    /// Renders the body of one skill.
    ///
    /// - Parameters:
    ///   - name: The id of the skill.
    ///   - skills: The skills registry.
    /// - Returns: The rendered body, `nil` when the registry no longer has
    ///   the skill, or ``AgentRunFailure/skillRenderFailed(skill:description:)``
    ///   when the render fails.
    private static func render(_ name: String, in skills: SkillsRegistry) async -> Render {
        do {
            return .success(try await skills.call(id: name))
        } catch is UnknownSkillError {
            return .success(nil)
        } catch {
            return .failure(.skillRenderFailed(skill: name, description: String(describing: error)))
        }
    }

    /// Gives the warning for one entry of the `skills` key.
    ///
    /// - Parameters:
    ///   - name: The entry.
    ///   - isModelVisible: The visibility of the skill, or `nil` when no
    ///     skill of the registry has the name.
    /// - Returns: The warning, or `nil` for a skill that can load.
    private static func finding(for name: String, isModelVisible: Bool?) -> AgentFinding? {
        switch isModelVisible {
        case .none:
            unknownSkillFinding(name)
        case .some(false):
            hiddenSkillFinding(name)
        case .some(true):
            nil
        }
    }
}

extension AgentEnvironment {
    /// The `skills:` preload of each run: the skills registry of the
    /// environment, with the visibility rule of its `skills` tool.
    var skillsPreload: AgentSkillsPreload {
        AgentSkillsPreload(skills: skills, isVisible: skillsVisibility)
    }
}
