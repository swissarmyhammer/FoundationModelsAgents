# Skills and agents

This document tells how the agents of this package relate to the skills of
FoundationModelsSkills. It gives the decisions that transfer from skills to
agents, it tells how one marketplace plugin gives skills and agents, and it
gives the rule for partials. The full design is in [plan.md](../plan.md).

## Skills and agents are separate

Skills and agents are separate things. A skill is text that a model reads in
its current context. An agent is a new context with its own system prompt, its
own tools, and its own session.

An agent uses skills through its `skills:` preload and through the `skills` tool:

- The `skills:` key of the agent file names skills. At run start, the run
  gets the rendered body of each named skill from the `SkillsRegistry`, and
  adds the body to the instructions of the new session. An unknown skill or a
  skill that is not visible gives a warning, and the run does not use it.
- The `skills` tool is one entry of the `ToolCatalog`. A run that has this
  tool can find a skill and use it while the run works.

To run a skill in its own context, a prompt tells an agent that has the `skills` tool to use the named skill.
The skill then works in the context of that agent, and the caller gets only the
final text of the run.

The agent
[security-reviewer.md](../Examples/agent-library/marketplace/plugins/code-tools/agents/security-reviewer.md)
of the fixture library preloads the skill `review` with `skills: [review]`.
The same plugin gives a skill with that name:
[review/SKILL.md](../Examples/agent-library/marketplace/plugins/code-tools/skills/review/SKILL.md).
The `SkillsRegistry` finds the skill by its id, thus a higher skill layer can
give a different copy.

## What transfers from skills to agents

A skill body goes into the current context. An agent body is the system
prompt of a new context. Decisions about the file, the catalog, and the tool
surface transfer. Decisions about text in the current context do not.

The section numbers in the table are the sections of
[plan.md](../plan.md).

| Skills decision | Agents |
|---|---|
| Extras stack; marketplace layers below local layers; cached catalog; `DotfolderWatcher`, `layerUpdates`, `onReload` | Same (§4) |
| A plugin gives `skills/` in the layer | Same: the plugin gives `agents/` in the same layer (§6) |
| Split and decode raw frontmatter; render the body later; trust by layer | Same (§4) |
| Lenient retry for a `description:` with an unquoted `:` | Same (§4) |
| The folder name is the id; a `name` mismatch is a warning | Same: the file name is the id (§4.1). Claude takes the id from `name`; a Claude file whose `name` is its file name loads with no warning. |
| One marketplace layer; the later plugin wins a name | Same: one flat `agents/` folder (§6) |
| Name rules, length limits, severities, diagnostics with provenance | Same (§4, §10) |
| `disable-model-invocation`, `user-invocable` | Same (§4, §9.4) |
| Description built from the catalog, with a limit and four forms | Same (§9.1) |
| The schema pins the ids at `make`; an unknown id is a corrective answer | Same (§9.1) |
| Plain-text answers; `CorrectiveOutcome` | Same (§9.1) |
| CLI from `OperationCLIDriver`; demo; example library with broken files | Same (§9.4, §13) |
| Guard tests on the source | Same (§15) |
| `use skill` gives the body to the caller | Not copied. `start agent` gives the body to a new session. |
| Argument substitution and quarantine | `$ARGUMENTS` only: this package puts the prompt into the body as a quarantined span (§4.3). |
| Shell injection; `RenderPolicy` | Not copied. A system prompt is static. |
| `preload: true` into the host's instructions | Not copied. The `skills:` key preloads into the agent's own context (§5). |
| Resources and `run script` under the skill folder | Not copied. An agent is one file. |
| `search skill` | Not copied. `list agents` gives the full catalog. |
| `OperationDescribing`, `ForkableTool` | Not copied (§9.5). |
| A slash command delivers the raw body as a prompt | Different: a slash command starts a run (§9.4). |
| Skills and agents | Separate things. An agent uses skills: the `skills:` preload (§5) and the `skills` tool. To run a skill in its own context, prompt an agent that has the `skills` tool to use the named skill. |

## One plugin gives skills and agents

One `MarketplaceStore` serves the `SkillsRegistry` and the `AgentRegistry`.
One plugin gives `skills/` and `agents/`, and both go into the same
marketplace layer:

```
<marketplace layer root>/
  review/SKILL.md          the skills of all plugins
  _partials/house-rules.md the partials of the plugins
  agents/
    security-reviewer.md   one .md file for each agent of all plugins
    doc-writer.md
```

- The skills registry reads the skill folders of the layer. The agents
  registry reads the `.md` files directly in `agents/` of the layer, one
  level. The file name is the id of the agent.
- When two plugins give the same file name, the later plugin wins, and the
  store records one diagnostic.
- A local layer (`defaults`, `user`, or `project`) is above each marketplace
  layer. Thus a local copy of an agent file hides the marketplace copy.
- The selection `.all` or `.plugins([...])` gives the agents of the selected
  plugins. The selection `.skills([...])` gives no agents.
- When the marketplace changes, the store reports `layerUpdates`, and the
  two registries build their catalogs again. A run that operates keeps its
  definition.

The fixture
[marketplace.json](../Examples/agent-library/marketplace/.claude-plugin/marketplace.json)
has two plugins. The plugin
[code-tools](../Examples/agent-library/marketplace/plugins/code-tools) gives a
skill, an agent, and a partial. The plugin
[docs-tools](../Examples/agent-library/marketplace/plugins/docs-tools) gives
one agent.

## The partials rule

The partials of a plugin are in `<plugin root>/_partials/`. The skills and the
agents of the plugin use the same partials. The snapshot of a marketplace
copies each `_partials/` folder from the source root down to each selected
skill into `_partials/` of the layer. A more specific copy of a name replaces
a less specific copy.

An agent body includes a partial with `{% include "house-rules.md" %}`. The
include resolves from the folder of the document up to the layer root, and
never above the layer root:

1. `agents/_partials/house-rules.md`.
2. `_partials/house-rules.md`.

At each level, the render examines each layer, highest layer first. The first
copy that it finds wins. Thus a more specific folder of a lower layer wins
over the root of a higher layer.

- A marketplace agent sees the partials of its own marketplace and of the
  local layers.
- A local agent sees the partials of the local layers only.
- The `defaults` layer renders trusted. All other layers render untrusted.
- An include that does not resolve fails the run with `bodyRenderFailed`.

The agent
[security-reviewer.md](../Examples/agent-library/marketplace/plugins/code-tools/agents/security-reviewer.md)
includes the partial
[house-rules.md](../Examples/agent-library/marketplace/plugins/code-tools/_partials/house-rules.md)
of its plugin.
