# Skills and agents

This document tells how the agents of this package relate to the skills of
FoundationModelsSkills. It gives the decisions that transfer from skills to
agents, it tells how one marketplace plugin gives skills and agents, and it
gives the access rule of the `agents` tool and the rule for partials.

## Skills and agents are separate

Skills and agents are separate things. A skill is text that a model reads in
its current context. An agent is a new context with its own system prompt, its
own tools, and its own session.

An agent uses skills through its `skills:` preload and through the `skills` tool:

- The `skills:` key of the `AGENT.md` file names skills. At run start, the run
  gets the rendered body of each named skill from the `SkillsRegistry`, and
  adds the body to the instructions of the new session. An unknown skill or a
  skill that is not visible gives a warning, and the run does not use it.
- The `skills` tool is one entry of the `ToolCatalog`. A run that has this
  tool can find a skill and use it while the run works.

To run a skill in its own context, a prompt tells an agent that has the `skills` tool to use the named skill.
The skill then works in the context of that agent. The caller gets the
messages that the run sends with `send caller` while it works, and the final
text of the run when it ends.

The agent
[security-reviewer/AGENT.md](../Examples/agent-library/marketplace/plugins/code-tools/agents/security-reviewer/AGENT.md)
of the fixture library preloads the skill `review` with `skills: [review]`.
The same plugin gives a skill with that name:
[review/SKILL.md](../Examples/agent-library/marketplace/plugins/code-tools/skills/review/SKILL.md).
The `SkillsRegistry` finds the skill by its id, thus a higher skill layer can
give a different copy.

## The access rule

An agent gets the operations of the `agents` tool that start agents only from
an explicit `tools` entry: `Agent`, `Agent(a, b)`, or `agents`. Each run with
a caller can send messages to that caller. A run that a `start agent` call
started has a caller, thus it gets an `agents` tool with `send agent` and
`send caller` also when its `tools` key does not list `Agent`. A host-started
run has no caller, and with no `Agent` entry it gets no `agents` tool.
`disallowedTools: Agent` removes the tool in each case. The table of the
operations of the tool of a run is in
[DelegatingWithTheAgentsTool.md](../Sources/FoundationModelsAgents/FoundationModelsAgents.docc/DelegatingWithTheAgentsTool.md).

## What transfers from skills to agents

A skill body goes into the current context. An agent body is the system
prompt of a new context. Decisions about the file, the catalog, and the tool
surface transfer. Decisions about text in the current context do not.

| Skills decision | Agents |
|---|---|
| Extras stack; marketplace layers below local layers; cached catalog; `DotfolderWatcher`, `layerUpdates`, `onReload` | Same |
| A plugin gives `skills/` in the layer | Same: the plugin gives `agents/` in the same layer |
| Split and decode raw frontmatter; render the body later; trust by layer | Same |
| Lenient retry for a `description:` with an unquoted `:` | Same |
| The folder name is the id; a `name` mismatch is a warning | Same: an agent is the folder `agents/<name>/AGENT.md`, and the folder name is the id. A Claude file `agents/<name>.md` has the old format: it gives no agent and one warning that tells you to move it to `agents/<name>/AGENT.md`. |
| One marketplace layer; the later plugin wins a name | Same: one flat `agents/` folder with one folder for each agent |
| Name rules, length limits, severities, diagnostics with provenance | Same |
| `disable-model-invocation`, `user-invocable` | Same |
| Description built from the catalog, with a limit and four forms | Same |
| The schema pins the ids at `make`; an unknown id is a corrective answer | Same |
| Plain-text answers; `CorrectiveOutcome` | Same |
| CLI from `OperationCLIDriver` | Not copied. The package has no command line. |
| Demo; example library with broken files | Same |
| Guard tests on the source | Same |
| `use skill` gives the body to the caller | Not copied. `start agent` gives the body to a new session. |
| Argument substitution and quarantine | `$ARGUMENTS` only: this package puts the prompt into the body as a quarantined span. |
| Shell injection; `RenderPolicy` | Not copied. A system prompt is static. |
| `preload: true` into the host's instructions | Not copied. The `skills:` key preloads into the agent's own context. |
| Resources and `run script` under the skill folder | The agent folder holds resources: each file of the folder other than `AGENT.md`. `AgentDefinition.folderURL` gives the folder of the winning layer. No operation gives the resources yet, and there is no `run script`. |
| `search skill` | Not copied. `list agents` gives the full catalog. |
| `OperationDescribing`, `ForkableTool` | Not copied. |
| A slash command delivers the raw body as a prompt | Different: a slash command starts a run. |
| Skills and agents | Separate things. An agent uses skills: the `skills:` preload and the `skills` tool. To run a skill in its own context, prompt an agent that has the `skills` tool to use the named skill. |

## One plugin gives skills and agents

One `MarketplaceStore` serves the `SkillsRegistry` and the `AgentRegistry`.
One plugin gives `skills/` and `agents/`, and both go into the same
marketplace layer:

```
<marketplace layer root>/
  review/SKILL.md                         the skills of all plugins
  _partials/house-rules.md                the partials of the plugins
  agents/
    security-reviewer/AGENT.md            one folder for each agent of all plugins
    security-reviewer/checklist.md        a resource of the agent
    doc-writer/AGENT.md
```

- The store finds the skills and the agents with a scan of the folders of
  the marketplace. It reads no catalog file. A folder that holds `SKILL.md`
  is a skill, and a folder that holds `AGENT.md` is an agent. The scan has
  no depth limit, thus `plugins/<name>/skills/` and `plugins/<name>/agents/`
  load. The snapshot copies each agent folder to `agents/<name>/`.
- The skills registry reads the skill folders of the layer. The agents
  registry reads each folder `agents/<name>/AGENT.md` of the layer. The folder
  name is the id of the agent.
- When two plugins give the same agent name, the later plugin wins, and the
  store records one diagnostic.
- A local layer (`defaults`, `user`, or `project`) is above each marketplace
  layer. Thus a local copy of an agent folder hides the marketplace copy.
- The selection `.all` gives the skills and the agents. The selection
  `.skills([...])` gives the named skills and no agents.
- When the marketplace changes, the store reports `layerUpdates`, and the
  two registries build their catalogs again. A run that operates keeps its
  definition.

The fixture [marketplace](../Examples/agent-library/marketplace) has two
plugins. The plugin
[code-tools](../Examples/agent-library/marketplace/plugins/code-tools) gives a
skill, an agent with a resource, and a partial. The plugin
[docs-tools](../Examples/agent-library/marketplace/plugins/docs-tools) gives
one agent.

## The partials rule

The partials of a plugin are in `<plugin root>/_partials/`. The skills and the
agents of the plugin use the same partials. The snapshot of a marketplace
copies each `_partials/` folder from the source root down to each selected
skill and each agent into `_partials/` of the layer. A more specific copy of a
name replaces a less specific copy. A `_partials/` folder in an agent folder
goes with the agent folder.

An agent body includes a partial with `{% include "house-rules.md" %}`. The
include resolves from the folder of the document up to the layer root, and
never above the layer root:

1. `agents/<name>/_partials/house-rules.md`, in the agent folder.
2. `agents/_partials/house-rules.md`.
3. `_partials/house-rules.md`.

At each level, the render examines each layer, highest layer first. The first
copy that it finds wins. Thus a more specific folder of a lower layer wins
over the root of a higher layer.

- A marketplace agent sees the partials of its own marketplace and of the
  local layers.
- A local agent sees the partials of the local layers only.
- The `defaults` layer renders trusted. All other layers render untrusted.
- An include that does not resolve fails the run with `bodyRenderFailed`.

The agent
[security-reviewer/AGENT.md](../Examples/agent-library/marketplace/plugins/code-tools/agents/security-reviewer/AGENT.md)
includes the partial
[house-rules.md](../Examples/agent-library/marketplace/plugins/code-tools/_partials/house-rules.md)
of its plugin.
