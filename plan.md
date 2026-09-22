# Plan: FoundationModelsAgents — Claude-style sub-agents for Foundation Models

A Swift package that loads [Claude Code sub-agent](https://code.claude.com/docs/en/sub-agents)
files from a stack of directories and marketplaces, and gives them to
[Foundation Models](https://developer.apple.com/videos/play/wwdc2026/241/)
through one tool, `agents`. Each run drives one
[`FoundationModelsRouter`](../FoundationModelsRouter/README.md) session.
`FoundationModelsExtras` gives the file stack, the marketplace, the watcher,
and the render. This package gives only the agent layer: the definition, the
catalog, the delegation rules, and the tool.

**Target: macOS 27, on-device.**

---

## 1. Principles

- **An agent run is a new Router session** in the same process. It gets a
  task, works in the background with its own context and its own tools, and
  gives back one final text. The caller keeps its own context.
- **An agent is a tool.** One `OperationTool` named `agents` with four
  operations: `list agents`, `start agent`, `check agent`, `cancel agent`.
  An agent can have this tool, so agents can start agents. `maxDepth` is 3.
- **Agents learn from Skills (§2).** The same file kind, the same stack, the
  same catalog-in-a-description. Not copied: what Skills does because a
  skill adds text to the current context.
- **A marketplace gives agents as it gives skills.** One plugin holds
  `skills/` and `agents/`. One store, one layer, two registries (§6).
- **Not a code-mode surface.** No `OperationDescribing`, no `ForkableTool`
  (§9.5).
- **The minimum layer.** This package owns the frontmatter decode, the
  validation, the catalog, the model match, the tool resolution, the runner,
  and the tool. File access, watching, rendering, and marketplace work are
  in Extras. Guard tests enforce the boundary (§15).
- **One session system, one recorder, one display: the Router's.** No
  session type, no tool loop, no compaction, no recorder, no display types.
- **A run posts one final message.** `start agent` returns at once. When the
  run finishes, its final message is posted into the calling session and
  recorded there. The next prompt of that session reads it. This package
  starts no turn in a calling session.
- **`check agent` is a plain tool call.** It answers at once.
- **A run finishes after its children.** A run whose agent started agents
  does not finish while one is open.
- **A sub-agent is isolated.** It sees the task prompt only. Only its final
  text comes back. The detail is in its transcript.
- **One run is one task.** No follow-up into a finished run.
- **The Router decides which models exist.** The `model` value must match a
  Router slot or a chosen model reference. No alias table here.
- **Parallel, and honest about the GPU.** `maxConcurrentAgents` limits how
  many runs have a turn in operation. The Router serializes generation on
  each resident model.

## 2. Skills and agents — what transfers

A skill body goes into the current context. An agent body is the system
prompt of a new context. Decisions about the file, the catalog, and the tool
surface transfer. Decisions about text in the current context do not.

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
| Argument substitution and quarantine | `$ARGUMENTS` only: this package puts the prompt into the body as a quarantined span (§4.3). A skill with `agent:` renders in Skills, then becomes the prompt (§9.4). |
| Shell injection; `RenderPolicy` | Not copied. A system prompt is static. |
| `preload: true` into the host's instructions | Not copied. The `skills:` key preloads into the agent's own context (§5). |
| Resources and `run script` under the skill folder | Not copied. An agent is one file. |
| `search skill` | Not copied. `list agents` gives the full catalog. |
| `OperationDescribing`, `ForkableTool` | Not copied (§9.5). |
| A slash command delivers the raw body as a prompt | Different: a slash command starts a run (§9.4). A skill with `agent:` is a command of this package, not of Skills. |

## 3. Architecture

```
┌─ Layer 3  FM adapter ───────────────────────────────────────────────────┐
│  AgentsTool    one OperationTool "agents": four operations, one noun    │
│  AgentRunner   actor: the run limit, the run index, the children        │
│  AgentRun      drives ONE RoutedSession; state and result               │
├─ Layer 2  AgentRegistry ────────────────────────────────────────────────┤
│  the cached catalog of `agents/*.md` over the local and marketplace     │
│  layers; the file name is the id; rebuilt on a watch or an update       │
├─ Layer 1  AgentDefinition ──────────────────────────────────────────────┤
│  AgentFrontmatter.decode + validation of one located document           │
└─────────────────────────────────────────────────────────────────────────┘
  Extras:       DotfolderStack · FrontmatterDocumentStack · DotfolderWatcher
                StenciledDotfolderStack · QuarantinedText · AgentsMd
                SlashCommand · SlashCommandProviding
                Operations (OperationTool, @Operation, OperationResolver)
  Marketplace:  MarketplaceLayerProviding · MarketplaceLayer · MarketplaceStore
  Router:       LanguageModelProfile slots · RoutedSession · ToolContext
                · recording
  Skills:       SkillsRegistry
```

- Layers 1 and 2 have no model. They keep `model` as text; the runner
  matches it (§7).
- **The host makes the dependencies:** the `DotfolderStack`, the
  `MarketplaceStore`, the `Router` and its resolved `LanguageModelProfile`,
  and the `SkillsRegistry`. `AgentRegistry.init` takes the stack and the
  store. `AgentEnvironment.init` takes the profile and the skills registry.
  None has a default. The host session and the sub-agents use the same
  instances.
- The Router comes in at one point: `AgentEnvironment.profile`.
  `makeSession` is on `profile.standard` and `profile.flash`.

## 4. The catalog

### 4.1 Layers and identity

- **Layers**, lowest to highest: `marketplace[0] < … < marketplace[n] <
  defaults < user < project`. The local layers are the host's
  `DotfolderStack`. The marketplace layers come from
  `MarketplaceLayerProviding.marketplaceLayers()`. A host that wants
  `~/.claude` appends a local layer.
- **Agent files are the `.md` files directly in `agents/`** of the combined
  view, one level. The folder name is `MarketplaceLayer.agentsDirectoryName`.
- **The file name is the id.** `agents/code-reviewer.md` is `code-reviewer`.
  A `name` that is not equal to the file name is a warning.
- **The highest layer wins a path.** Each lower copy is hidden, with an
  advisory.
- **Provenance.** Each definition keeps its URL, its layer, and its
  `MarketplaceProvenance` when it has one.
- **The catalog is cached.** `catalog()` does no I/O. The registry rebuilds
  and swaps atomically on a `DotfolderWatcher` change, on `layerUpdates`, or
  on `reload()`. `onReload` publishes each new catalog.

### 4.2 Format

YAML frontmatter and a body. The body is the system prompt.

```markdown
---
name: code-reviewer
description: Reviews code for quality and best practices.
tools: Read, Grep
model: flash
---

You are a code reviewer. Analyze the code and give specific feedback.
```

| Tier | Fields | Behavior |
|---|---|---|
| 1 — enforced | `name`, `description` (required); `tools`, `disallowedTools`; `model`; `skills`; `maxTurns`; `compactionPrompt`; `disable-model-invocation`, `user-invocable` | Full semantics (§5–§9) |
| 2 — data | `color`; `background`; unknown keys | On `AgentListing`. `background: false` gets an advisory; all runs are background runs. |
| 3 — not supported | `permissionMode`, `mcpServers`, `hooks`, `memory`, `effort`, `isolation`, `initialPrompt` | Advisory, then ignored. A Claude file loads. |

- `compactionPrompt` is the fold prompt of this agent; absent gives
  `CompactionPrompt.default`.
- `isModelVisible = description is valid && disable-model-invocation != true`:
  in the description, the schema, and `list agents`.
- `isUserInvocable = user-invocable != false`: a slash command (§9.4).

### 4.3 Load

1. **Split and decode** through a `FrontmatterDocumentStack` on the plain
   stack of all layers:

   ```swift
   let plain = DotfolderStack(layers: marketplaceLayers.map(\.layer) + stack.layers)
   let documents = FrontmatterDocumentStack(base: plain, decode: AgentFrontmatter.decode, onDiagnostic: collect)
   let folder = MarketplaceLayer.agentsDirectoryName
   for (id, _) in plain.enumerate(folder, suffix: ".md") {       // one level; id = file name
     let file = documents.item(at: "\(folder)/\(id).md")          // Located<FrontmatterDocument<AgentFrontmatter>>
   }
   ```

   The frontmatter is never rendered. `AgentFrontmatter.decode` uses Yams and
   never throws. On a failure it retries one time with the Skills rule (quote
   a `description:` with an unquoted `:`) and records a note.
2. **Validate.** `AgentDefinition.init` applies this table:

   | Rule | Severity |
   |---|---|
   | No frontmatter block, or no decode after the retry | skip |
   | File name not 1–64 of `[a-z0-9-]`, or a leading, trailing, or doubled hyphen | skip |
   | `name` absent or not equal to the file name | warning; the file name stays the id |
   | `description` absent or empty | warning; not model-visible |
   | `description` longer than 1024 | warning |
   | Unknown tool or skill name (§5) | warning |
   | Unknown name in `disallowedTools` | warning, shown first (§5) |
   | `model` with no match (§7, by the runner) | warning |
   | Tier 3 field, `background: false`, a decode note, an unknown key | advisory |
   | A lower-layer file with the same name | advisory |

   A bad file does not stop a good file next to it.
3. **Render the body at run start**, in two passes:
   1. **`$ARGUMENTS`.** This package replaces each `$ARGUMENTS` in the body
      with the prompt, as a quarantined span of a `QuarantinedText`, so
      prompt text is never a template. A body with no `$ARGUMENTS` is
      unchanged. The prompt is also the first user turn (§8), with or
      without `$ARGUMENTS`.
   2. **Stencil.** `StenciledDotfolderStack.render(_:at:in:)` on the
      quarantined text: the document path `agents/<id>.md`, the winning
      layer, the host's `variables`. An include resolves from the folder of
      the document up to the layer root: `agents/_partials/x.md`, then
      `_partials/x.md`. At each level, every layer is checked, highest
      first; the first copy found wins, so a more specific folder of a lower
      layer wins over the root of a higher layer. `defaults` renders
      trusted; all other layers render untrusted. A marketplace document
      sees its own marketplace and the local layers; a local document sees
      the local layers only.

   A render failure fails the run with `bodyRenderFailed`.

## 5. Tools and skills for a sub-agent

- **`ToolCatalog`**: `name → factory of any Tool`. Each run gets new
  instances. The `skills` tool is one entry.
- **Resolution (Claude semantics).** No `tools` key gives the full catalog.
  `disallowedTools` applies first, then `tools`. The MCP patterns
  `mcp__<server>`, `mcp__<server>__*`, `mcp__*` are prefix matches. An
  unknown name is a warning and is skipped. An unknown name in
  `disallowedTools` is shown first, because a dropped deny gives more access
  than the author wanted.
- **The `agents` tool** is in the catalog under the name `agents`, so the
  same rules apply. `Agent(a, b)` gives the tool with its names limited to
  `a` and `b`. Each run gets its own instance from `AgentsTool.make`.
- **`skills:` preload.** At run start, `SkillsRegistry.call(id:)` gives each
  rendered body, and the run appends it to the instructions of the new
  session. An unknown or not-visible skill is a warning and is skipped.
- **`maxTurns`** is enforced on tool calls with a counting decorator. Above
  the limit, the run cancels its turn and fails with `hitMaxTurns`, with the
  partial text. Claude counts turns and stops silently; this is tighter.

## 6. Marketplaces of agents

### 6.1 The layer

```
<marketplace layer root>/
  review/SKILL.md          skills, as today
  _partials/sah-*.md       the partials of the plugin root
  agents/
    code-reviewer.md       one .md file for each agent, of all plugins
    test-writer.md
```

- One `MarketplaceStore` serves `SkillsRegistry` and `AgentRegistry`. The
  agents registry reads the `.md` files directly in
  `MarketplaceLayer.agentsDirectoryName` of each layer, one level.
- The later plugin wins a file name, with one `MarketplaceDiagnostic`.
- A local copy overrides a marketplace copy (§4.1).
- The partials of a plugin are `<plugin root>/_partials/`, for the skills and
  the agents. An include in an agent body resolves from `agents/` up to the
  layer root (§4.3). The `swissarmyhammer/skills` marketplace gives 8 agents
  and `_partials/sah-*.md` at its root.
- Selection: `.all` and `.plugins([...])` give agents; `.skills([...])`
  gives none.
- A marketplace update reports `layerUpdates`; the registries rebuild. A run
  in operation keeps its definition.
- Fetch and snapshot diagnostics stay in the host's store.

### 6.2 What Extras gives

The Extras snapshot of a marketplace holds the agents and the partials of
each selected plugin:

1. Catalog plugins: the `agents` list of the plugin entry when present, else
   each `.md` directly in `<plugin source>/agents/`. Copied to
   `agents/<file name>`.
2. A tree with no catalog: the `.md` files directly in `<source root>/agents/`.
3. One level. The later plugin wins a name, with one diagnostic.
4. `.skills([...])` gives no agents.
5. Extras reads no agent frontmatter.
6. The `_partials/` folder of each folder from a source root down to each
   selected skill is copied to `<snapshot>/_partials/`, least specific
   first. A more specific copy of a name replaces a less specific one with
   no diagnostic. Two folders at the same depth: the later one wins, with
   one diagnostic. Thus `_partials/` at the plugin root and
   `skills/_partials/` both work, and in a flat snapshot an agent sees them
   all.
7. `StenciledDotfolderStack.render(_:at:in:)` takes the document path
   relative to the layer root. An include resolves from the folder of the
   document up to the layer root, never above it; at each level every layer
   is checked, highest first, and the first copy wins. `render(_:in:)`
   searches the layer root only.

The folder name is `MarketplaceLayer.agentsDirectoryName == "agents"`. This
package reads `marketplace.layer.root/agents/` for each layer of
`provider.marketplaceLayers()`, and again on each `layerUpdates` value. A
`file://` source with `path:` gives its folder unchanged.

## 7. Model selection

| `model:` | Result |
|---|---|
| absent / `inherit` | the slot of the caller; for a host-started run, `AgentEnvironment.defaultSlot` (`.standard`) |
| `standard` or `flash` | that slot |
| the `chosen.stringValue` of a slot, or its part before `@` | that slot (`standard` when the two slots share a model) |
| other (`opus`, `sonnet`, `embedding`, unknown) | warning, then `inherit` |

The match needs the profile, so `runner.catalog()` does it, and a run matches
again when it starts. Layer 1 checks only that `model` is a non-empty string.
A Claude marketplace file with `model: sonnet` loads, gets the warning, and
runs on `inherit`. No `CLAUDE_CODE_SUBAGENT_MODEL`, no `model` tool
parameter.

## 8. Execution — one run, one Router session

1. **Resolve** `registry.catalog().definition(named:)`. The run keeps it.
2. **Render the body** (§4.3) with the prompt as `$ARGUMENTS`. A failure
   fails the run.
3. **Instructions**, in order: `AgentsMd.documents(from:)` for the working
   directory, outermost first; the body; the `skills:` bodies.
4. **Resolve tools** (§5) with the counting decorator.
5. **Match the model** (§7) and make the session:

   ```swift
   let model = slot == .flash ? profile.flash : profile.standard
   let session = model.makeSession(
     instructions: instructions, workingDirectory: workingDirectory, tools: tools,
     budget: environment.budget(model.contextTokens),      // default TokenBudget(limit:)
     compactionPrompt: definition.compactionPrompt ?? .default,
     agentSpawn: spawn)                                     // §8.2; nil for a host-driven run
   ```

6. **Drive one turn** with `session.streamEvents(to: prompt)`. Nothing goes
   to the caller during the turn.
7. **Do not finish while a child is open.** A child posts its final message
   into this session (§9.2); the Router stages it and emits `runSettled`.
   Each time a child finishes, the run calls `session.dispatchNextPrompt()`.
   The Router runs one turn with the staged posts and its fixed prompt
   ("Background work you started has settled… Act on it, or say what you
   did with it."). The model can start more children. Each such turn counts
   toward `maxTurns`. This touches only the session of the run.
8. **Finish.** When no child is open and no post is unread, the text of the
   last turn is the result. The run posts its final message (§9.2) and closes
   its session.

The Router gives compaction, overflow recovery, `TokenBudget.toolOutputLimit`,
correlated tool events, and the recording. The working directory defaults to
`AgentEnvironment.workingDirectory`. A run gets no git snapshot and no memory
files, and cannot be resumed.

### 8.1 Objects

```
AgentDefinition  (authored file)   static data; one for each name
      │  runner.start(name, prompt)
      ▼
AgentRun  (id = session id)        ONE delegated task: scheduling and cancel
      │  drives; does not give it to other code
      ▼
RoutedSession  (Router)            made and closed with the run
```

- Runs of one agent are independent. `AgentRun.id` is its session id and its
  recording directory name.
- A run holds its session and does not give it to other code. The session
  lives as long as the task. A finished run holds no session.
- The record of a finished run (id, name, state, final text) stays for
  `check agent`. `maxRetainedRuns` removes the oldest; a removed id gives a
  corrective answer.

### 8.2 Lineage

```swift
let context = ToolContext.current   // nil outside a Router session
let spawn = context.map {
  SessionSidecar.AgentSpawn(parentSessionId: $0.sessionID, parentToolCallId: $0.completionToken)
}
```

The sub-agent session is a Router root session (`parentId == nil`), recorded
at `<recordingsDir>/<routerId>/<sessionId>/`. The Router writes `agentSpawn`
into `session.json` and onto the `.session` event. A host-driven run and a
slash-command run have `nil`. The agent name is an argument of the
`start agent` call that `parentToolCallId` points to. The chain goes through
all levels. This package adds no lineage data.

## 9. Delegation

### 9.1 The tool

`AgentsTool.make(context:catalogCharacterLimit:)` wraps an
`OperationTool<AgentsToolContext>`, as `SkillsCatalogTool` does. `make` reads
the catalog one time; a new tool for each session and for each run.

**The description**, as in Skills. Fixed sentences that are never cut:

> An agent is a model session that works in the background. Each agent
> starts with an empty context and sees only the prompt that you give it, so
> put all that the agent needs in the prompt. To give a task to an agent,
> call this tool with {"op": "start agent", "name": "<name>", "prompt":
> "<the full task>"}. The call returns at once. When the agent finishes, its
> final message comes to you as a tool result. Your answer is the text of
> your last turn, so give your final answer after you have the results of
> the agents that you started. You can ask about a run with {"op": "check
> agent", "id": "<id>"}.

Then the model-visible agents under `catalogCharacterLimit` (default
`SkillsTool.defaultCatalogCharacterLimit`, 8000), in the first form that
fits: full `- name: description` lines; descriptions cut to 200 characters;
names only; as many names as fit plus "`N` more agents are not listed. See
them with `list agents`." An empty catalog: "No agents are installed now."

**The schema** pins `name` to the model-visible names at `make`, limited by
`Agent(a, b)`. After a reload: a changed agent runs with the new definition;
a removed agent gives a corrective answer with the current names; an added
agent is in `list agents` and in the next tool, not in this schema.

**Answers are plain text**, `CorrectiveOutcome`: `.success` or
`.corrective(String)`. A correction is a text result in the same turn, never
a thrown error, never a post.

| op | parameters | success | corrective |
|---|---|---|---|
| `list agents` | `filter?` | One `- name: description` line for each model-visible match, then the delegation sentence. "No agents are available." is a success. | none |
| `start agent` | `name`, `prompt` | At once: "Agent `name` started with the id `id`. Its final message comes to you when it finishes." | Unknown or removed name, with the available names. A name outside `Agent(a, b)`. Depth above `maxDepth`. The run limit (§9.3). A blank prompt. |
| `check agent` | `id?` | At once, never waits. Finished: "Agent `name` (`id`) finished." and the full text. Failed or cancelled: the state and the reason. Running: "is running: `lastEvent`" and, after its turn, "It waits for `N` agents that it started." No `id`: one block for each run of this caller. | Unknown id, or an id of a different caller, with this caller's ids. |
| `cancel agent` | `id` | The `CancelOutcome`. | As `check agent`. |

Verb aliases: `stop` → `cancel`, `run` → `start`, `status` → `check`,
`show` → `list`.

### 9.2 The final message

- `start agent` reads `ToolContext.current`, gives it to the run, starts the
  run as a runner task, and returns. It posts nothing. The run id is the
  `completionToken` of the call.
- The run posts nothing while it works. All its work is in its own
  transcript.
- On finish, the run calls `context.post(_:)` one time with a `.completed`
  event whose `detail` is the full final text. The Router journals it into
  the calling transcript at once, stamped with the tool, the op, and the
  token, and stages it. The next prompt of the calling session reads it.
- **Always `.completed`.** The event kinds are `.progress`, `.completed`,
  `.elicitation`; only `.completed` is a terminal, and only a staged
  `.completed` makes `dispatchNextPrompt()` run a turn. A failed run posts
  `.completed` with `outcome` set and "Agent `name` (`id`) failed: reason."
  A cancelled run posts "Agent `name` (`id`) was cancelled."
- **Post, then finish.** The run posts before the runner marks it finished.
- **One post.** The Router drops a second terminal for the same token.
- **The signal is the Router's.** Each journaled `.completed` post emits
  `SessionEvent.runSettled(event)`, into the turn in flight or into
  `streamSessionEvents()`. A chat host waits for the next user prompt. An
  autonomous host calls `dispatchNextPrompt()`. `respond(to:)` does not read
  these posts after its turn; that drain is for Router mailbox runs only.
- **A closed caller.** `close()` does not know these runs. The host calls
  `runner.cancelRuns(caller: sessionID)` before it closes a session that has
  the `agents` tool. `runner.stop()` cancels all.
- **Outside a Router session** (`ToolContext.current == nil`) `start agent`
  makes its own id, no final message comes back, and the model uses
  `check agent`.

### 9.3 `AgentRunner`

An actor that owns each `AgentRun`. Not a session system, a tool loop, a
recorder, or a display model.

- **The limit.** `maxConcurrentAgents` counts runs with a turn in operation.
  Only `start agent` checks it. At the limit it answers: "`N` agents are
  working now, and that is the limit. Do this part of the task yourself, or
  start the agent when one of them finishes." No queue. A run that waits for
  its children holds no slot; a child-delivery turn never checks the limit,
  so the count can go above the limit for a short time. The Router's
  generation gate serializes the calls. A fan-out of siblings does not block
  their children.
- **Children.** A run records the runs it started and finishes only after
  they finish. A cancel, or a failure with open children (`hitMaxTurns`, a
  context error), cancels the children, waits for their tasks, then closes
  the session and posts.
- **`maxTurns`** counts the task turn and each child-delivery turn.
- **Depth.** A host-started run has depth 1; a child has its parent's depth
  plus 1. `maxDepth` is the limit.
- **The index.** `runs`, `run(id:)`, token → run, and for each run its
  caller (`ToolContext.sessionID` or `nil`), slot, and depth; plus the
  records of finished runs.
- `runner.catalog()`: the registry catalog with the model match.
- Host-driven fan-out:
  `async let a = runner.start("code-reviewer", prompt: p1).result()`.
- `run.cancel()` cancels the turn and the open children. `cancelRuns(caller:)`
  cancels each open run of one caller. `stop()` cancels all and closes all
  sessions.
- One runner holds one profile.

### 9.4 Slash commands and the CLI

`AgentRunner` conforms to `SlashCommandProviding`. `commands(workingDirectory:)`
gives two kinds of command. Each has an `.action` body that starts a
host-driven run, waits for it, and gives the final text. The body is never a
prompt for the host session.

- **An agent.** One command for each user-invocable agent: `name`,
  `description`, `argumentHint: "<task>"`. The text after the name is the
  prompt, unchanged. `/code-reviewer check the diff` is the user's
  delegation.
- **A skill with `agent:`.** One command for each skill of the
  `SkillsRegistry` whose `agent:` key names an agent of the catalog: the
  skill's `id`, `description`, and `argumentHint`. The body calls
  `registry.call(id:arguments:)` with the text after the name, so Skills
  renders the skill with `$ARGUMENTS`, `$N`, `$name`, the shell injection, and
  the partials, as for `use skill`. The rendered text is the prompt of a run
  of the named agent. `/implement ^abc123` renders `implement` with
  `$ARGUMENTS` = `^abc123` and gives the result to a new session of
  `implementer`. An `agent:` that names no agent of the catalog is an
  `AgentDiagnostic` warning, and the skill gets no command here.

In both kinds, the prompt is `$ARGUMENTS` of the agent body (§4.3): the
typed text, or the rendered skill.

Skills gives `SkillListing.agent` from the frontmatter and leaves such a skill
out of its own `commands()`, so one name has one provider. `use skill` on such
a skill gives the rendered text, as for any skill. `commandUpdates` follows
the `onReload` of the agents and of the skills.

`AgentsCLI.makeDriver(runner:)` gives an `OperationCLIDriver` over the four
operations (`agents agent list`, `agents agent start --name … --prompt …`).
The CLI `start` waits for the run and prints the final text. `check` and
`cancel` are for a host process that stays alive.

### 9.5 Not a code-mode surface

`AgentsTool` does not conform to `OperationDescribing` or `ForkableTool`. A
run is a session with its own turns, not a script verb, and the lineage and
the final message need a Router session as the caller. A host registers the
`agents` tool directly on its session, next to Multitool if it uses one.

## 10. Recording and diagnostics

- Each run has `transcript.jsonl` and `session.json` in its Router session
  directory. `Router(recordingsDir:recorder:recordingLevel:redact:)` controls
  it. This package writes no recording.
- A host that shows agent work shows Router sessions. The lineage joins a
  sub-agent to the call that started it.
- `AgentCatalog.diagnostics` is `[AgentDiagnostic]`, the shape of
  `SkillDiagnostic`: severity (`advisory`, `warning`, `skip`), the agent name
  when known, provenance (layer index, layer root, file URL,
  `MarketplaceProvenance`), and a message. `runner.catalog()` adds the
  `model` warnings.
- `AgentReloadReport`: agent counts, model-visible count, marketplace counts,
  slash-command names, diagnostic counts.

## 11. Dependencies

| Package | Products | Used for |
|---|---|---|
| `FoundationModelsRouter` | `FoundationModelsRouter` | `LanguageModelProfile`, `ModelSlot`, `ModelRef`, `RoutedSession`, `SessionEvent`, `ToolContext`, `OperationEvent`, `TokenBudget`, `CompactionPrompt`, `SessionSidecar.AgentSpawn` |
| `FoundationModelsExtras` | `FoundationModelsExtras`, `Marketplace`, `Operations`, `OperationsCLI` | `DotfolderStack`, `FrontmatterDocumentStack`, `FrontmatterDocument`, `Located`, `DotfolderWatcher`, `StenciledDotfolderStack`, `QuarantinedText`, `AgentsMd`, `SlashCommand`, `SlashCommandProviding`; `MarketplaceLayerProviding`, `MarketplaceLayer`, `MarketplaceProvenance`; `OperationTool`, `@Operation`, `OperationResolver`; `OperationCLIDriver` |
| `FoundationModelsSkills` | `FoundationModelsSkills` | `SkillsRegistry` (`call(id:arguments:)`, `commandListing()`, `onReload`); `SkillListing.agent` (S1); `SkillsTool.defaultCatalogCharacterLimit`; `CorrectiveOutcome` |
| Yams, ULID.swift | | `AgentFrontmatter.decode`; ids |

All sibling APIs are shipped, except S1 (§14). One library target,
`FoundationModelsAgents`, and one executable, `agents-demo`. Siblings are
remote dependencies on `main`. Swift tools 6.2, `.macOS("27.0")`.

Skills brings in `FoundationModelsRanker` and `FoundationModelsMetadataRegistry`,
which export a protocol `AgentSession`. It is unrelated. This package does
not use that name.

## 12. API sketch

```swift
// The host makes the dependencies.
let stack   = DotfolderStack(name: "myapp", workingDirectory: projectURL)
let market  = MarketplaceStore(sources: [MarketplaceSource("https://github.com/acme/claude-plugins")],
                               layout: SkillMarketplaceLayout.skills)
let router  = Router(recordingsDir: recordingsURL)
let profile = try await router.resolve(profile: coding, reporting: progress)
let skills  = SkillsRegistry(marketplaces: market, stack: stack, watch: true)

// The catalog. No Router here.
let agents = AgentRegistry(marketplaces: market, stack: stack,
                           variables: ["project": "acme"], watch: true)
await market.start()
agents.catalog().listing                       // [AgentListing]
agents.catalog().diagnostics                   // [AgentDiagnostic]
for await catalog in agents.onReload { … }

let skillsTool = try await SkillsTool.make(registry: skills)
var tools = ToolCatalog()
tools.register("skills") { skillsTool }

let env = AgentEnvironment(profile: profile, skills: skills,
                           workingDirectory: projectURL, tools: tools,
                           defaultSlot: .standard, maxConcurrentAgents: 4, maxDepth: 3)
let runner = AgentRunner(registry: agents, environment: env)

// Host-driven.
let report = try await runner.start("code-reviewer", prompt: "Review:\n\(diff)").result()
let commands = await runner.commands(workingDirectory: projectURL)   // [SlashCommand]

// Model-driven, from a Router session.
let agentsTool = try await AgentsTool.make(context: AgentsToolContext(runner: runner))
let root = profile.standard.makeSession(instructions: "…", workingDirectory: projectURL,
                                        tools: [agentsTool] + otherTools)
for try await event in root.streamEvents(to: userPrompt) {
  // .runSettled: an agent run has posted its final message
}
let followUp = try await root.dispatchNextPrompt()   // reads staged posts; nil when none

await runner.cancelRuns(caller: root.id)             // the Router does not know these runs
await root.close()
```

`AgentRegistry` has the `SkillsRegistry` initializers: `init(stack:variables:watch:)`,
`init(layers:variables:watch:)`, `init(marketplaces:stack:variables:watch:)`.

Types: `AgentFrontmatter`, `AgentDefinition`, `AgentListing`, `AgentRegistry`,
`AgentCatalog`, `AgentDiagnostic`, `AgentReloadReport`, `AgentEnvironment`,
`ToolCatalog`, `AgentsTool`, `AgentsToolContext`, `AgentRunner`, `AgentRun`
(`id`, `agent`, `caller`, `depth`, `state`, `recordingDirectory`, `result()`,
`cancel()`), `AgentRunState` (`running`, `finished(String)`,
`failed(AgentRunFailure)`, `cancelled`), `AgentRunFailure`
(`bodyRenderFailed`, `hitMaxTurns`, …), `AgentsCLI`.

## 13. Examples

```
Examples/
  agent-library/            fixture layers; the tests use them too
    defaults/agents/          code-reviewer.md (flash; tools: Read, Grep)
                              test-writer.md (standard; body has $ARGUMENTS)
                              lead.md (tools: Agent(code-reviewer, test-writer))
    defaults/_partials/       house-rules.md
    defaults/skills/review/   SKILL.md with `agent: code-reviewer` and `$ARGUMENTS`
    user/agents/              a user copy of code-reviewer.md
    project/.agents/agents/   project agents; one with user-invocable: false
    marketplace/              .claude-plugin/marketplace.json
                              plugins/code-tools/_partials/house-rules.md
                              plugins/code-tools/skills/review/SKILL.md
                              plugins/code-tools/agents/security-reviewer.md
                              plugins/docs-tools/agents/doc-writer.md
    broken/agents/            bad-colon-description.md, missing-description.md,
                              bad-name.md, no-frontmatter.md,
                              unknown-model.md, unknown-disallowed-tool.md
  agents-demo/              (default)       the CLI
                            --chat          a Router session with the agents tool;
                                            the lead agent starts two agents
                            --fan-out       host-driven runs on the two slots
                            --watch         an AgentReloadReport on each onReload
                            --marketplace   the marketplace fixture as a source
```

`--chat` needs a resolved profile. The marketplace fixture is a git source.

## 14. Milestones

- **M1 — `AgentDefinition`.** Decode with the retry, the rule table, the
  visibility axes, tool-list parsing. Hermetic tests with `agent-library/broken`.
- **M2 — `AgentRegistry`.** Layers, the one-level read, the file name as id,
  provenance, the cache, the rebuild on watch and `layerUpdates`, `onReload`,
  `reload()`, `AgentReloadReport`. Guard tests. Tests with
  `MarketplaceFixtures` and a fixture provider of the §6.1 shape. *Needs M1.*
- **M3 — `AgentRun`.** One run end to end: the two render passes,
  instructions, tools, the model match, the budget, `agentSpawn`, the final
  text, close. `run.cancel`. *Needs M1.*
- **M4 — `AgentsTool`.** The description forms, the pinned schema, the
  answers, the four operations, the final message through `ToolContext`, the
  path outside a Router session. `agents-demo --chat`. *Needs M2, M3.*
- **M5 — Scheduler and nested runs.** The limit, `cancelRuns(caller:)`,
  `check agent` with no id, `maxRetainedRuns`, `stop()`. The `agents` tool in
  a run, finish after children, `inherit` from a calling run, `maxDepth`,
  cancel that goes down. `agents-demo --fan-out`. *Needs M4.*
- **S1 — Skills: the `agent:` key.** In `FoundationModelsSkills`:
  `SkillListing.agent` from the frontmatter; a skill with `agent:` is not in
  the Skills `commands()`; `use skill` is unchanged.
- **M6 — Semantics and user surfaces.** `skills:` preload, `disallowedTools`
  and MCP patterns, `Agent(a, b)`, `maxTurns`. `SlashCommandProviding` for
  agents and for skills with `agent:`, `AgentsCLI`, the demo default,
  `--watch`, `--marketplace`. *Needs M4, S1.*
- **M7 — Marketplace agents end to end.** The integration cases with a real
  `MarketplaceStore` and a git source. *Needs M2.*
- **M8 — Finish.** DocC, README with a compiled example, a document on
  skills and agents. *Needs M5, M6, M7.*

## 15. Testing

**Guard tests**, from Skills, on each line of `Sources/FoundationModelsAgents/`:
`LoadingBoundaryTests` (the 16 forbidden names: `FileManager`, `FileHandle`,
`String(contentsOf`, `Data(contentsOf`, `resourceValues`,
`contentsOfDirectory`, `DispatchSource`, `O_EVTONLY`,
`resolvingSymlinksInPath`, `FrontmatterDocument.split`, `TemplateEngine`,
`TemplateContext`, `TemplateValue`, `WellKnownValues`, `import Stencil`,
`import libgit2`; an unused exemption fails), `NoStandardOutWriteTests`,
`NoDotfolderStackExtensionTests`, `NoCodeModeConformanceTests`,
`ReadmeExampleTests`.

**Hermetic tests** with `agent-library`, `MarketplaceFixtures`, and the
Router test-support sessions; no real model:

- Layers: a project file replaces lower copies with advisories; the file name
  is the id and a `name` mismatch warns; a subfolder is not read; `{{ }}` in
  frontmatter stays text; the colon retry; `defaults` trusted and all else
  untrusted; a local body cannot include a marketplace-only partial
  (`bodyRenderFailed`); each `broken/` file gives its diagnostic and the good
  files load.
- `$ARGUMENTS`: each `$ARGUMENTS` in the body is the whole prompt; a prompt
  that holds `{{ project }}` or `{% include %}` lands as text, not as a
  template; a body with no `$ARGUMENTS` is unchanged; the prompt is the
  first user turn in every case.
- Marketplace: agents of the layer are in the catalog with provenance; the
  same layer feeds a `SkillsRegistry` and a `skills:` preload of its own
  plugin works; a body includes a partial of `<layer root>/_partials/`, and a
  partial in `agents/_partials/` wins over it; a project agent wins
  with an advisory; the folder is `MarketplaceLayer.agentsDirectoryName`; no
  `agents/` folder gives nothing; `layerUpdates` gives a new catalog; a
  `model: sonnet` file warns and runs on `inherit`.
- Tool: the four description forms; the fixed sentences never cut;
  `disable-model-invocation` and `user-invocable`; each corrective answer;
  `start agent` posts nothing during its call; the final message is the only
  post and holds the full text, also when long; a failed or cancelled run
  posts `.completed`; `check agent` never waits.
- Commands: `/name text` gives `text` as the prompt, unchanged; `/implement
  x` renders the skill with `$ARGUMENTS` = `x` and starts `implementer` with
  the rendered text; an `agent:` that names no agent warns and gives no
  command; a skill with `agent:` is in the runner's commands only.
- Reload: add, change, remove; a burst gives one final catalog; a run in
  operation is unchanged; the pre-reload tool behavior of §9.1;
  `commandUpdates` after an agent reload and after a skill reload.
- Runs: the model match table; a finished run holds no session;
  `maxRetainedRuns`; a parent finishes after its child and reads the child
  post in a delivery turn; a failing parent cancels its children first; with
  `maxConcurrentAgents` 2, two waiting siblings hold no slot and their
  children start; the limit and `maxDepth` corrective answers; a caller
  cannot address another caller's run; `cancelRuns(caller:)`; `stop()`.

**Integration suite** in a nested `IntegrationTests/` package (Swift Testing,
`.serialized`, an environment variable, small `mlx-community` models):

- A local file, a git-marketplace plugin (M7), and a `file://` folder each
  become a live sub-agent.
- The flash model reference runs on the flash slot.
- Full circle: the root calls `start agent`, the sub-agent uses a tool, the
  final message is in the root transcript, the next turn reads it, and
  `check agent` gives the same text.
- Nested: `agentSpawn` links three sessions; `parentToolCallId` joins to the
  `start agent` call.
- A slash command gives its result. Two slots overlap. `cancel agent` stops a
  run. A live edit is used by the next delegation while an old run completes.

## 16. To verify during implementation

- `ToolContext.completionToken` joins to the tool call in the Router
  transcript, for `AgentSpawn.parentToolCallId`. (M3)
- A `.completed` post through a kept `ToolContext`, after the plain call has
  returned, is journaled and staged, and the next prompt reads it. The call
  must post nothing before it returns. Confirm through an `OperationTool`
  operation and with a detail longer than 4 096 characters. (M4)
- A post during a turn of the calling session stays staged and is never
  lost. (M4, M5)
- `dispatchNextPrompt()` with a staged `.completed` runs one turn; with
  nothing staged it gives `nil`. (M5)
- `runSettled` is emitted for a `.completed` post with no mailbox run behind
  it. (M4)
- A post into a closed session does no harm. (M5)
- Plain-text answers use the Skills method: the operation gives text, the
  wrapper decodes the JSON string that `OperationTool` makes. (M4)
- The Extras layer has the §6.1 shape, for a catalog and for a tree, with
  the partials at `<snapshot>/_partials/`. Confirm with the
  `swissarmyhammer/skills` marketplace. (M7)
- `render(_:at:in:)` with `agents/<id>.md` reaches `<layer root>/_partials/`.
  (M3)
- A `file://` source with `path:` gives the folder unchanged. (M2)
- `registry.call(id:arguments:)` with one element that holds the whole typed
  text gives the same `$0`, `$1`, and `$name` values as `use skill`. (M6)
- `render(_:at:in:)` on a `QuarantinedText` never scans a quarantined span,
  so `{{ }}` and `{% %}` inside a substituted prompt stay text. (M3)

---

### Sources

- Claude Code sub-agents — https://code.claude.com/docs/en/sub-agents
- Claude Code plugins — https://code.claude.com/docs/en/plugins
- FoundationModelsRouter — ../FoundationModelsRouter/README.md
- FoundationModelsExtras — ../FoundationModelsExtras/plan.md
- FoundationModelsSkills — ../FoundationModelsSkills/README.md, docs/operations.md, docs/marketplaces.md
- FoundationModelsMultitool — ../FoundationModelsMultitool/README.md
- WWDC26 — https://developer.apple.com/videos/play/wwdc2026/241/, https://developer.apple.com/videos/play/wwdc2026/242/
