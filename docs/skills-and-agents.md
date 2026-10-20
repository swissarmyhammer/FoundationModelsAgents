# Skills and agents

This document tells how the agents of this package relate to the skills of
FoundationModelsSkills. It gives the decisions that transfer from skills to
agents, it tells how one marketplace plugin gives skills and agents, and it
gives the access rule of the `agents` tool, the search of `find agents`, the
rule for partials, and the agent folders with the default agent.

## Skills and agents are separate

Skills and agents are separate things. A skill is text that a model reads in
its current context. An agent is a new context with its own system prompt, its
own tools, and its own session.

An agent uses skills through its `skills:` preload and through the `skills` tool:

- The `skills:` key of the `AGENT.md` file names skills. At run start, the run
  gets the rendered body of each named skill from the `SkillsRegistry`, and
  adds the body to the instructions of the new session. An unknown skill or a
  skill that the `skills` tool hides gives a warning, and the run does not use
  it.
- The `skills` tool is one entry of the `ToolCatalog`. A run that has this
  tool can find a skill and use it while the run works.

The host gives one `SkillsRegistry` to `AgentEnvironment.make`. The
environment makes the `skills` tool from that registry, and puts it in its
`ToolCatalog` under the name `skills`. The preload reads the same registry,
with the visibility rule of the tool. Thus an agent cannot preload a skill
that its `skills` tool hides, and the tool cannot show a skill of a different
registry. The host gives `environment.skillsTool` to its root session. A
`skills` entry in the tool catalog of the host is a programmer error.

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
| `enabled: false` turns the item off; the nearest copy wins; a wrong value fails closed | Same: `FrontmatterEnablement` of Extras reads the key, and the agent scan applies it after its shadowing |
| Description built from the catalog, with a limit and four forms | Same |
| The id is a plain string, checked against the live catalog at call time; an unknown id is a corrective answer | Same: the `name` field of `start agent` |
| Plain-text answers; `CorrectiveOutcome` | Same |
| CLI from `OperationCLIDriver` | Not copied. The package has no command line. |
| Demo; example library with broken files | Same |
| Guard tests on the source | Same |
| `use skill` gives the body to the caller | Not copied. `start agent` gives the body to a new session. |
| Argument substitution and quarantine | `$ARGUMENTS` only: this package puts the prompt into the body as a quarantined span. |
| Shell injection; `RenderPolicy` | Not copied. A system prompt is static. |
| `preload: true` into the host's instructions | Not copied. The `skills:` key preloads into the agent's own context. |
| Resources and `run script` under the skill folder | The agent folder holds resources: each file of the folder other than `AGENT.md`. `AgentDefinition.folderURL` gives the folder of the winning layer. No operation gives the resources yet, and there is no `run script`. |
| `search skill` | Replaced by D61: `find agents` of the `agents` tool. See "Find an agent" below. `list agents` still gives the full catalog. |
| `OperationDescribing`, `ForkableTool` | Not copied. |
| A slash command delivers the raw body as a prompt | Different: a slash command starts a run. |
| Skills and agents | Separate things. An agent uses skills: the `skills:` preload and the `skills` tool. To run a skill in its own context, prompt an agent that has the `skills` tool to use the named skill. |

## Find an agent

Decision D61 of the SwissArmyHammer app replaces the earlier decision "`search
skill`: not copied". A model finds an agent for a task in the same way that it
finds a skill: `{"op": "find agents", "query": "<the task>"}`. The search
first ranks the descriptions of the agents with keywords and with the
embedding model of the profile. Then the selection model picks the best
matches. The selection model is the `skillsSelectionModel` of
`AgentEnvironment.make`, thus the `skills` tool and the `agents` tool choose
with one model. With no selection model, the call gives the rank of the
search.

The search uses the selection parts of FoundationModelsSkills again, and does
not copy them: `MetadataSearcher` in `.auto` mode with a `SelectionConfig`,
and a second `MetadataSearcher` in `.retrieval` mode as the fallback. When the
answer of the selection model does not decode, the fallback ranks the query,
and the call does not fail. This is the assembly of
`SkillsTool.make(registry:model:)`.

- The index holds only the agents that the model can see
  (`AgentDefinition.isModelVisible`). Thus an agent with no valid description,
  and an agent with `disable-model-invocation: true`, are never found.
- The call then keeps only the agents that the tool can start: not the agent
  of the run, and only the names of `Agent(a, b)`.
- `AgentRunner` holds one index. The index follows each catalog of
  `AgentRegistry.onReload`, thus an agent that a reload adds is found.
- The answer has one `- name: description` line for each match, best first,
  then the sentence that tells how to start an agent. `limit` gives the most
  lines, and the default is 5.

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
- An agent of the agent folder form (`<id>/AGENT.md` of a local layer) sees
  the partials of its own layer only.
- The `defaults` layer renders trusted. All other layers render untrusted.
- An include that does not resolve fails the run with `bodyRenderFailed`.

The agent
[security-reviewer/AGENT.md](../Examples/agent-library/marketplace/plugins/code-tools/agents/security-reviewer/AGENT.md)
includes the partial
[house-rules.md](../Examples/agent-library/marketplace/plugins/code-tools/_partials/house-rules.md)
of its plugin.

## Agent folders and the default agent

`AgentRegistry` reads all its layers from the `DotfolderStack` of the host.
There is no separate input for a folder of agent folders. A host gives its
root settings folder, for example the synced `Agents/` folder of an app, as
one layer of the stack, for example the `user` layer. The folder of the
session is the `project` layer, and it wins. Each local layer holds its agents
in two forms: the dotfolder form `agents/<id>/AGENT.md`, and the agent folder
form, with no `agents/` level:

```
<root>/
  AGENT.md                    the default agent: the id `default`
  _partials/house-rules.md    the partials of the agents of this layer
  _skills/                    a settings folder: not an agent
  helper/AGENT.md             the agent `helper`
```

- The layers are `marketplace[0] < … < marketplace[n]`, then the local layers
  in the order of the stack, for example `defaults < user < project`. No layer
  goes between two local layers. A marketplace layer reads the dotfolder form
  only.
- A child folder of the layer root whose name is not a valid id, for example
  `_skills/`, `_rules/`, `_partials/`, or `.git/`, is not an agent. It gives no
  diagnostic.
- In one layer, `<id>/AGENT.md` wins over `agents/<id>/AGENT.md`, and the
  hidden copy gives the hidden-copy advisory.
- `<root>/AGENT.md` is the default agent. Its id is the fixed id `default`, and
  `AgentCatalog.defaultAgent` gives it. A host starts its root session from it
  when it is present, and uses its own instructions when it is `nil`. Its
  `name` is a display name, and the rule table does not compare it with the id.
- The root `AGENT.md` wins over `<root>/default/AGENT.md`, which gives one
  warning. A `default` agent of a higher layer, for example
  `agents/default/AGENT.md` of the project, wins over the root file.
- An include of an agent of the agent folder form walks `<name>/_partials/`,
  then `_partials/` of the layer root. The default agent uses `_partials/` of
  the layer root. An agent of the agent folder form reads the partials of its
  own layer only. An agent of the dotfolder form reads the partials of each
  local layer, thus also `_partials/` of a lower layer root.
- A placeholder `.AGENT.md.<suffix>` of a sync service, or an `AGENT.md` that
  the build cannot read, gives one `skip`: "the agent document is not local
  yet". Only the exact name `AGENT.md` is an agent document; a conflict copy
  `AGENT 2.md` and each different hidden file, for example `.env.local`, is a
  resource. A coordinated read that fails gives one `skip` with its cause.
  These rules apply to each document of the agent folder form.
- An agent never works in its own folder by default, also an agent of the
  agent folder form. A request folder (`AgentRunner.start(_:prompt:workingDirectory:)` or
  the `workingDirectory` field of `start agent`) wins. Else the run works in
  the folder of its creator, the session that starts it: a child run works in
  the folder of its parent, and a run that a host session (not a run) or the
  host API starts works in `AgentEnvironment.workingDirectory`. A relative
  `workingDirectory` of `start agent` starts from the folder of the creator. A
  slash command gives the folder of the session that runs it as the request
  folder, thus a command run works in the folder of the session. A host that
  wants a run in the folder of the agent gives `AgentDefinition.folderURL` as
  the request folder.
- With `watch: true`, the watcher watches each local layer root. A layer root
  that does not exist gives no agent and no diagnostic.

The package holds no code of a sync service: no container id, no path of the
service, and no ubiquity API. The SwissArmyHammer app gives its iCloud
`Agents/` folder as the `user` layer of its stack. The guard suite `No cloud sync code` holds
the package source to this rule.
