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
  gives back one final text when it ends. The caller keeps its own context.
- **An agent is a tool.** One `OperationTool` named `agents` with six
  operations: `list agents`, `start agent`, `check agent`, `cancel agent`,
  `send agent`, `send caller` (noun synonym `parent`). An agent whose `tools`
  key lists `Agent` has each operation, so agents can start agents (§5). Each
  run with a caller has `send agent` and `send caller` (§9.3). `maxDepth` is
  3.
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
- **A run can send messages to its caller while it works, and it gives one
  final message when it ends.** `start agent` is a background call: it waits
  for the run up to the settle period of the session
  (`SessionConfiguration.inlineSettleGrace`, default
  `ToolMount.defaultInlineSettleGrace`). A run that ends in that time gives
  its final message as the output of the call. A run that continues gives the
  pending envelope of the Router. A message of `send caller` comes to the
  calling session as mail, and the run continues. When a run that continued
  ends, its final message is the detail of the Router run, and it comes to
  the calling session as mail. The pump of the Router
  delivers the mail and starts an answer to it. This package starts no answer
  in a calling session.
- **`check agent` is a plain tool call.** It answers at once.
- **A run finishes after its children.** A run whose agent started agents
  does not finish while one is open.
- **A sub-agent is isolated.** It sees the task prompt and the messages of
  its caller only. Its messages and its final text go back to the caller. The
  detail is in its transcript.
- **One run is one task.** A caller can send a message to a run that is still
  running (`send agent`). A run that ended gets no message, and the call
  gives a corrective.
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
| Argument substitution and quarantine | `$ARGUMENTS` only: this package puts the prompt into the body as a quarantined span (§4.3). |
| Shell injection; `RenderPolicy` | Not copied. A system prompt is static. |
| `preload: true` into the host's instructions | Not copied. The `skills:` key preloads into the agent's own context (§5). |
| Resources and `run script` under the skill folder | Not copied. An agent is one file. |
| `search skill` | Not copied. `list agents` gives the full catalog. |
| `OperationDescribing`, `ForkableTool` | Not copied (§9.5). |
| A slash command delivers the raw body as a prompt | Different: a slash command starts a run (§9.4). |
| Skills and agents | Separate things. An agent uses skills: the `skills:` preload (§5) and the `skills` tool. To run a skill in its own context, prompt an agent that has the `skills` tool to use the named skill. |

## 3. Architecture

```
┌─ Layer 3  FM adapter ───────────────────────────────────────────────────┐
│  AgentsTool    one OperationTool "agents": six operations               │
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
- **The catalog is cached.** `init` stores its inputs and reads no file. The
  host calls `try await registry.load()` one time, after `market.start()`;
  `load()` is `async` so that each call site shows the I/O. `catalog()` does
  no I/O and gives an empty catalog before `load()`. The registry rebuilds
  and swaps atomically on a `DotfolderWatcher` change, on `layerUpdates`, or
  on `try await reload()`. `onReload` publishes each new catalog.

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
| 1 — enforced | `name` (a warning when absent or not equal to the file name; the file name is the id); `description` (a warning when absent or empty; the agent is then not model-visible); `tools`, `disallowedTools`; `model`; `skills`; `maxTurns`; `compactionPrompt`; `disable-model-invocation`, `user-invocable` | Full semantics (§5–§9) |
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
   | `disallowedTools` not a list of text, or a list with an item that is not text | warning, shown first; the deny cannot be read in full, thus the agent gets no tools |
   | `tools` not a list of text, or a list with an item that is not text | warning; only the text entries give tools, thus a value that is not a list gives no tools |
   | `maxTurns` not a whole number, or not greater than 0 | warning; the limit is 1 pass |
   | `model` with no match (§7, by the runner) | warning |
   | Tier 3 field, `background: false`, the colon retry note, a wrong type on another key, an unknown key | advisory |
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
- **Resolution (Claude semantics).** No `tools` key gives each tool of the
  catalog, but not the operations of the `agents` tool that start agents.
  `disallowedTools` applies first, then
  `tools`. The MCP patterns `mcp__<server>`, `mcp__<server>__*`, `mcp__*`
  are prefix matches. An unknown name is a warning and is skipped. An unknown
  name in `disallowedTools` is shown first, because a dropped deny gives more
  access than the author wanted.
- **The `agents` tool.** Only an explicit `tools` entry gives the operations
  that start agents: `Agent`, `Agent(a, b)`, or `agents`. An agent with no
  `tools` key gets only the message operations, and only in a run with a
  caller. Thus an agent can start agents only when its author lists the tool,
  and each run with a caller can send messages to it. `Agent(a, b)` gives the
  tool with its names limited to `a` and `b`. `disallowedTools: Agent` removes
  the tool of each grant. Each run gets its own instance from
  `AgentsTool.make`. The mount table is in §9.3.
- **`skills:` preload.** At run start, `SkillsRegistry.call(id:)` gives each
  rendered body, and the run appends it to the instructions of the new
  session. An unknown or not-visible skill is a warning and is skipped.
- **`maxTurns`** counts the passes of the control loop. In each pass the
  model generates, then it calls tools and the loop goes around again, or it
  answers and the loop ends. Each pass records one transcript entry, and the
  Router emits `entryRecorded` with kind `.toolCalls` or `.response` for it.
  The run has one counter for all its answers: the answer to the task prompt
  and each answer to mail (§8 step 7). One `streamSessionEvents()`
  subscription for the whole run counts the passes from the live events, and
  feeds the progress of `check agent`. While a submission runs, each
  `generationCall` is one pass, and an open tool record shows at least one
  pass. When the submission ends, the count of its `.toolCalls` and
  `.response` entries replaces its live count. One pass that calls three
  tools is one. Above the limit, the run stops its session and fails with
  `hitMaxTurns`, never as cancelled. The partial text is the reply of the
  answer that ended, or the text so far when the answer failed. Claude stops
  silently; this is tighter. No Router change.

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
| the `chosen.stringValue` of a slot, or its part before `@` | that slot; the Router gives the two slots two different models, and when they are one repository at two revisions, the part before `@` gives `standard` |
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
4. **Resolve tools** (§5).
5. **Match the model** (§7) and make the session:

   ```swift
   let model = slot == .flash ? profile.flash : profile.standard
   let session = model.makeSession(
     instructions: instructions, workingDirectory: workingDirectory, tools: tools,
     budget: environment.budget(model.contextTokens),      // default TokenBudget(limit:)
     compactionPrompt: definition.compactionPrompt ?? .default,
     agentSpawn: spawn)                                     // §8.2; nil for a host-driven run
   ```

6. **Send the task.** The run subscribes to `streamSessionEvents()` first,
   and follows that one subscription for its whole life. Then it sends the
   prompt as one message with `session.streamEvents(to: prompt)`. The pump of
   the Router runs the answer. During the answer, the run can send messages
   to its caller with `send caller` (§9.2). The task prompt is always the
   first message of the session: the run holds each caller message of
   `send agent` until it reads the start of the answer of the task prompt,
   then sends each held message in order.
7. **Answer the mail.** `start agent` is a background run of the Router
   (§9.1). The final message of each child is the detail of its Router run,
   and it comes to this session as mail (§9.2). Each message of a child
   (`SessionEvent.runMessage`) also comes as mail. The pump of the Router
   delivers the mail in a new submission and starts an answer to it, with no
   call of the run. The model can start more children in that answer. The
   passes of each answer count toward `maxTurns` (§5). This touches only the
   session of the run.
8. **End when idle.** A run ends when its session is idle. The run checks
   this after each answer and after each settled child. The session is idle
   when each child ended, when the session answered the final message of
   each pending envelope of the settled transcript and each message of a
   child, and when no caller message waits in the queue or in the hold of
   the run. The session answered a final message when no answer is open and
   a prompt that holds it comes before the newest transcript entry that a
   processed `SessionEvent.entryRecorded` named. The settled transcript can
   be ahead of the events that the run processed, thus a prompt alone is not
   proof of an answer. The reply of the last answer is the result. A run
   that started no child and got no caller message ends after the answer of
   its task. The run also ends when the count of passes goes
   above `maxTurns` (`hitMaxTurns`), when an answer fails, when the Router
   holds the mail and starts no answer for it
   (`SessionEvent.mailDeliveryPaused`; the run fails with
   `mailDeliveryPaused`), or when a caller cancels it. When the run ends, it
   records its final state at once, cancels its open children and waits for
   them, waits until the Router recorded the final message of each child,
   and closes its session. The `start agent` body of its own caller then
   gives the final message (§9.2).

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
  recording directory name. The setup of a run is `async`: `start` renders
  the body, awaits the `skills:` preload and the tool makers, and makes the
  session (§8 steps 2 to 5). `start` returns after the session exists, thus
  the id exists when `start` returns. A run whose setup fails has no session;
  it gets a new ULID and no recording.
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
> call the tool "agents" with the arguments {"op": "start agent", "name":
> "<name>", "prompt": "<the full task>"}. The value of "op" is an operation
> of the tool "agents", not the name of a tool. When the agent finishes in
> a few seconds, the call gives its final message. Else the agent works in
> the background, and its final message comes to you as a new message after
> you end your answer. Your answer is the text of your last turn, so
> give your final answer after you have the results of the agents that you
> started. You can ask about a run with {"op": "check agent", "id": "<id>"}.

Then the model-visible agents under `catalogCharacterLimit` (default
`SkillsTool.defaultCatalogCharacterLimit`, 8000), in the first form that
fits: full `- name: description` lines; descriptions cut to 200 characters;
names only; as many names as fit plus "`N` more agents are not listed. See
them with `list agents`." An empty catalog: "No agents are installed now."

**The schema** pins `name` to the model-visible names at `make`, limited by
`Agent(a, b)`. After a reload: a changed agent runs with the new definition;
a removed agent gives a corrective answer with the current names; an added
agent is in `list agents` and in the next tool, not in this schema.

**The mount of each operation.** `AgentsTool` conforms to `BackgroundTool`,
and each operation declares its own mount on its `@Operation`.
`start agent` declares `mount: ToolMount(mode: .background)`, with no
timeout: in a Router session the call is a background run of the Router. The
body of the call waits for the run and gives its final message (§9.2). `list agents`,
`check agent`, `cancel agent`, `send agent`, and `send caller` keep the
synchronous mount: each call gives its real answer in band. The tool states
no settle period of its own, thus a `start agent` call waits for the settle
period of the session. A run that ends in that time gives its final message
in band. A run that continues gives the pending envelope. `0` gives the
envelope at once. The `next` sentence of that envelope agrees with the
pump of the Router, which delivers mail only after the answer of the model
ends:

> This agent works in the background. Do not wait for it, and never guess
> its result. End your answer now, or do other work first: its final message
> comes to you as a new message after your answer ends. To see its state,
> call {"op": "check agent", "id": "<completion token>"}.

**Answers are plain text**, `CorrectiveOutcome`: `.success` or
`.corrective(String)`. A correction is a text result in the same answer,
never a thrown error, never mail.

| op | parameters | success | corrective |
|---|---|---|---|
| `list agents` | `filter?` | One `- name: description` line for each model-visible match, then the delegation sentence. "No agents are available." is a success. | none |
| `start agent` | `name`, `prompt` | In a Router session: the final message when the run ends in the settle period of the session; else the pending envelope, with the `next` sentence above, and the final message comes later as mail (§9.2). Outside a Router session: "Agent `name` started with the id `id`. Ask about it with {"op": "check agent", "id": "`id`"}." | Unknown or removed name, with the available names. A name outside `Agent(a, b)`. Depth above `maxDepth`. The run limit (§9.3). A blank prompt. |
| `check agent` | `id?` | At once, never waits. Finished: "Agent `name` (`id`) finished.", a blank line, and the full text. Failed: "Agent `name` (`id`) failed: reason." Cancelled: "Agent `name` (`id`) was cancelled." Running: "Agent `name` (`id`) is running." and, after the answer of its task prompt, "It waits for `N` agents that it started." Then four lines of progress from the live events of the run, never from its transcript: "Phase: " the task turn, the wait for the agents that it started, or an answer to a final message; "Passes: " the count of passes of all answers; "Last tools: " the names of the last five tool calls, or none; "Text so far: " the last 240 characters of the text of the current answer, after "..." when the text is longer, or none. The `id` is the id of a run, or the completion token of the `start agent` call from its pending envelope. No `id`: one block for each run of this caller. | Unknown id, or an id of a different caller, with this caller's ids. |
| `cancel agent` | `id` | The `CancelOutcome`. A run in operation: "The cancel of Agent `name` (`id`) was sent (`outcome`). The run stops when its turn ends." A run that ended: "The run ended before the cancel.", a blank line, and the `check agent` text of the run. | As `check agent`. |
| `send agent` | `id`, `message` | At once: "The message was sent to Agent `name` (`id`). Its final message comes to you as mail." The `id` is the id of a run of this caller, or the completion token of its `start agent` call. The run holds a message that comes before the answer of its task prompt starts, and its session gets the message after the task prompt. The run answers each message that it accepted before it ends. The prompt of the message is "Message from your caller: " and the text. The `id` of the session of the caller does the same as `send caller`. | A blank message. A run that ended: "The run `id` ended (`state`), and it gets no more messages. Start a new run." As `check agent` for an unknown id. |
| `send caller` | `message` | At once: "The message was sent to the session that started you. Continue your work. Your final message goes to that session when you end." The message is a `message` event of the `start agent` call that started the run, and it comes to the caller as mail (§9.2). The run continues. | A blank message. A session with no caller (a host session or a host-started run): "You have no caller." |

Verb aliases: `stop` → `cancel`, `run` → `start`, `status` → `check`,
`show` → `list`. Noun synonym: `parent` → `caller`, thus `send parent` is the
same call as `send caller`.

The tool of a run with a caller ends its description with the caller
sentence: "The session that started you has the id `id`. Send a message to it
with {"op": "send caller", "message": "..."}." A tool with only the message
operations (§9.3) does not read the catalog. Its description names no agent:
it tells how to call `send agent`, and that the run continues after the
message.

### 9.2 The final message

- **A background run.** `start agent` is a background run of the Router
  (§9.1). A run that continues past the settle period gives the pending
  envelope; a run that ends in it gives its final message in band. The
  body of the call reads `ToolContext.current`, gives it to the run, and adds
  the run under the completion token of the call. Thus `check agent`,
  `cancel agent`, and the canceler of the call find the run by that token.
- **Messages before the final message.** While the run works, it can send
  messages to its caller with `send caller`, and the caller can send
  messages to it with `send agent` (§9.1). All other work of the run is in
  its own transcript.
- **Message mail.** A message of `send caller` is a `message` event of the
  `start agent` call that started the run. The Router sends
  `SessionEvent.runMessage(event)` on `streamSessionEvents()`, and the pump
  delivers the message as mail with the line "[agents] start agent (`token`)
  message, still running: `message`". Message mail starts an answer the same
  as a final message: after the answer in operation ends, with no caller
  message and no call of the host. `mailOnlyAnswerLimit` and
  `mailDeliveryPaused` apply to it in the same way. A parent run answers each
  message of a child before it ends (§8 step 8), and the passes of these
  answers count toward `maxTurns`.
- **The final message is the run detail.** The body of the call waits for
  the run, and gives the `check agent` text of the final state as the detail
  of the Router run: "Agent `name` (`id`) finished.", a blank line, and the
  full reply of the last answer, also when it is longer than 4 096
  characters. The name and the id in the detail let the model join each
  final message to the run that it started. When two runs finish, the
  caller can tell which result came from which. A failed run gives "Agent
  `name` (`id`) failed: reason.", and a cancelled run gives "Agent `name`
  (`id`) was cancelled." The run itself calls no `context.post(_:)`.
- **Always `.completed`.** The Router makes the terminal of the call: a
  `.completed` event with the detail, stamped with the tool, the op, and the
  token. Only `.completed` is a terminal. The Router records one terminal for
  each call.
- **Mail, delivered by the Router pump.** The final message comes to the
  calling session as mail. The Router sends `SessionEvent.runSettled(event)`
  on `streamSessionEvents()`. The pump of the session delivers the mail
  after the answer in operation ends: it puts the mail at the start of the
  next submission, and starts an answer to it with no caller message and no
  call of the host. Thus the pending envelope tells the model to end its
  answer. A host sends its messages with `send(_:)` or `respond(to:)`, and
  reads each answer from its `streamSessionEvents()` subscription: an answer
  that answers only mail has empty `messageIds`. A run reads its own session
  the same way (§8 steps 7 and 8).
- **Mail that the Router holds.** `SessionConfiguration.mailOnlyAnswerLimit`
  limits a chain of answers that answer only mail, final messages and
  message mail both. At that limit the session
  holds new mail, starts no answer for it, and sends
  `SessionEvent.mailDeliveryPaused`. A run that gets that event fails with
  `mailDeliveryPaused`. A host sends a new message, and that message carries
  the held mail.
- **A closed caller.** `close()` does not know these runs. The host calls
  `runner.cancelRuns(caller: sessionID)` before it closes a session that has
  the `agents` tool. `runner.stop()` cancels all.
- **Outside a Router session** (`ToolContext.current == nil`) `start agent`
  works the same, no final message comes back, and the model uses
  `check agent`. The run has no caller, thus `send caller` gives "You have no
  caller."
- **Telemetry.** Each `send agent` call to a run of the caller and each
  `send caller` call with a message write one `agent.message.sent` log
  record, and add one `agent.message.sent` event to the active span of the
  call. The record holds the direction (`to_run`, `to_caller`), the outcome
  (`delivered`, `ended`, `no_caller`), the length of the message, and the
  name and the id of the run. It never holds the text of the message.

### 9.3 `AgentRunner`

An actor that owns each `AgentRun`. Not a session system, a tool loop, a
recorder, or a display model.

- **The limit.** `maxConcurrentAgents` counts runs with a turn in operation,
  except the run that calls `start agent`. After its answer, the calling run
  waits for the new child, and a run that waits holds no slot. Thus with
  `maxConcurrentAgents` 1, a parent and one child can work at one time.
  Only `start agent` checks the limit. At the limit it answers: "`N` agents are
  working now, and that is the limit. Do this part of the task yourself, or
  start the agent when one of them finishes." No queue. A run that waits for
  its children holds no slot; an answer to mail never checks the limit, so
  the count can go above the limit for a short time. The Router puts the
  generation calls of each model in one work queue for that model. A fan-out
  of siblings does not block their children.
- **Children.** A run records the runs it started and ends only when its
  session is idle (§8 step 8), thus after they end and after it answered
  each final message. A cancel, or a failure with open children
  (`hitMaxTurns`, a context error, `mailDeliveryPaused`), cancels the
  children, waits for their tasks, waits until the Router recorded the final
  message of each child, then closes the session.
- **`maxTurns`** counts the passes of the control loop in the answer to the
  task prompt and in each answer to mail, from the live events of the
  session (§5, §8 step 7).
- **Depth.** A host-started run has depth 1; a child has its parent's depth
  plus 1. `maxDepth` is the limit. A run at `maxDepth` gets no operation
  that starts agents, because each start from it would give only the depth
  corrective. A direct `start agent` call above the limit still gives that
  corrective.
- **The mount table.** `AgentSessionMaker` gives the grant of the `agents`
  tool of each run (`mountedGrant`), and `ToolResolver` mounts the tool:

  | The run | The grant |
  |---|---|
  | An `Agent`, `Agent(a, b)`, or `agents` entry, below `maxDepth` | `full`: each operation |
  | An `Agent` entry at `maxDepth`, with a caller | `messagingOnly`: `send agent`, `send caller` |
  | No `Agent` entry, with a caller | `messagingOnly`: `send agent`, `send caller` |
  | Each other case | no `agents` tool |

  A run has a caller when a `start agent` call started it: the tool keeps the
  `ToolContext` of that call and the id of its session. A host-started run
  has no caller. A `disallowedTools` entry that denies the `agents` tool wins
  over the table: the resolver then asks for no grant. When each run of an
  agent is at `maxDepth`, `runner.catalog()` gives a warning for its `Agent`
  entry: "each run of this agent is at maxDepth, thus its 'Agent' entry
  cannot start agents: a run with a caller gets only the message ops (send
  caller, send agent), and a host-started run gets no agents tool".
- **The index.** `runs`, `run(id:)`, `runs(caller:)`, and for each run its
  caller (`ToolContext.sessionID` or `nil`), slot, and depth; plus the
  records of finished runs.
- `runner.catalog()`: the registry catalog with the model match.
- Host-driven fan-out. `start` is `async throws(AgentRunnerError)` and
  `result()` is `async throws`:
  `async let a = try await runner.start("code-reviewer", prompt: p1).result()`,
  then `let reviewA = try await a`.
- `run.cancel()` cancels the answer and the open children. `cancelRuns(caller:)`
  cancels each open run of one caller. `stop()` cancels all and closes all
  sessions.
- A start whose setup is in operation (the render, the skills preload, the
  tool makers) is not in the index yet. `cancelRuns(caller:)` and `stop()`
  wait until the setup of each such start of the target ends, then cancel
  the run and wait for its final state, all before they return. Thus no run
  of the caller is in operation when `cancelRuns(caller:)` returns.
- After `stop()`, the runner starts no run: `runner.start` throws
  `AgentRunnerError.stopped`, and `start agent` gives a corrective.
- Before the first `registry.load()` or `registry.reload()`
  (`AgentRegistry.isLoaded` is `false`), `runner.start` and `AgentsTool.make`
  throw `AgentRunnerError.catalogNotLoaded`, and `agents agent start` gives
  the not-loaded text. Thus a host that did not call `load()` sees that
  mistake, and not an empty catalog.
- One runner holds one profile.

### 9.4 Slash commands and the CLI

`AgentRunner` conforms to `SlashCommandProviding`. `commands(workingDirectory:)`
gives one command for each user-invocable agent: `name`, `description`,
`argumentHint: "<task>"`. The `.action` body starts a host-driven run with the
text after the name as the prompt, unchanged, waits for it, and gives the final
text. The body is never a prompt for the host session. `/code-reviewer check
the diff` is the user's delegation. The prompt is `$ARGUMENTS` of the agent body
(§4.3). `commandUpdates` follows the `onReload` of the agents.

`AgentsCLI.makeDriver(runner:)` gives an `OperationCLIDriver` over five
commands. Each command has the noun `agent`:

- `agents agent list [--filter <text>]`: one `- name: description` line for
  each model-visible agent that matches, with no delegation sentence.
- `agents agent start --name <name> --prompt <task>`: a host-driven run
  (`runner.start(_:prompt:)`, no `ToolContext`, thus no mail). The command
  waits for the run and gives the final text.
- `agents agent check [--id <id>]` and `agents agent cancel --id <id>`: the
  answers of `check agent` and `cancel agent`. They are for a host process
  that stays alive.
- `agents agent send --id <id> --message <text>`: the answer of
  `send agent` for a host-started run of the runner. It is for a host
  process that stays alive. `send caller` has no command: a host is not a
  run, thus it has no caller.

`OperationCLIDriver` has no noun alias, and the tool op `list agents` has the
noun `agents`. Thus the CLI has its own five operations with the noun `agent`
over the same `AgentsToolContext` and texts. The tool ops keep their names.
The library writes nothing to standard output: the driver gives a `CLIResult`
to the host. A command that works gives one JSON string and exit code 0. A
corrective (a blank prompt, an unknown name, an unknown id) or a run that
fails gives the text of the reason and a non-zero exit code.

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
| `FoundationModelsSkills` | `FoundationModelsSkills` | `SkillsRegistry` (`call(id:)` for the `skills:` preload); `SkillsTool.defaultCatalogCharacterLimit`; `CorrectiveOutcome` |
| Yams, ULID.swift | | `AgentFrontmatter.decode`; ids |

All sibling APIs are shipped. One library target,
`FoundationModelsAgents`, and one executable, `agents-demo`. Siblings are
remote dependencies on `main`. Swift tools 6.2, `.macOS("27.0")`.

Skills brings in `FoundationModelsRanker` and `FoundationModelsMetadataRegistry`,
which export a protocol `AgentSession`. It is unrelated. This package does
not use that name.

## 12. API sketch

```swift
// The host makes the dependencies.
let agentStack = DotfolderStack(name: "agents", workingDirectory: projectURL)
let skillStack = DotfolderStack(name: "skills", workingDirectory: projectURL)
let market  = MarketplaceStore(sources: [MarketplaceSource("https://github.com/acme/claude-plugins.git")],
                               layout: SkillMarketplaceLayout.skills)
let router  = Router(recordingsDir: recordingsURL)
let profile = try await router.resolve(profile: coding, reporting: progress)

// The catalog. No Router here. The init reads no file.
let agents = AgentRegistry(marketplaces: market, stack: agentStack,
                           variables: ["project": "acme"], watch: true)
await market.start()
try await agents.load()                        // reads the files; after market.start()
agents.catalog().listing                       // [AgentListing]
agents.catalog().diagnostics                   // [AgentDiagnostic]
for await catalog in agents.onReload { … }     // take onReload before the change

// Skills are separate from agents. The SkillsRegistry builds in its init,
// thus the host makes it after market.start().
let skills = SkillsRegistry(marketplaces: market, stack: skillStack, watch: true)
let skillsTool = try await SkillsTool.make(registry: skills)
var tools = ToolCatalog()
tools.register("skills") { skillsTool }

let env = AgentEnvironment(profile: profile, skills: skills,
                           workingDirectory: projectURL, tools: tools,
                           defaultSlot: .standard, maxConcurrentAgents: 4, maxDepth: 3)
let runner = AgentRunner(registry: agents, environment: env)

// Host-driven. start is async throws(AgentRunnerError).
let run = try await runner.start("code-reviewer", prompt: "Review:\n\(diff)")
let report = try await run.result()
let commands = runner.commands(workingDirectory: projectURL)   // nonisolated; [SlashCommand]

// Model-driven, from a Router session.
let agentsTool = try await AgentsTool.make(context: AgentsToolContext(runner: runner))
let root = profile.standard.makeSession(instructions: "…", workingDirectory: projectURL,
                                        tools: [agentsTool] + otherTools)
let events = await root.streamSessionEvents()        // subscribe before the first message
_ = try await root.respond(to: userPrompt)           // a long run gives the pending envelope
for await case .answered(let answer) in events where answer.messageIds.isEmpty {
  print(answer.reply)                                // the pump answered a final message (mail)
}

await runner.cancelRuns(caller: root.id)             // the Router does not know these runs
await root.close()
```

The README example is the compiled form of this sketch. `ReadmeExampleTests`
checks that each Swift block of `README.md` is a copy of the text between the
markers in `ReadmeExampleSource.swift`, and runs that copy with the scripted
profile.

`AgentRegistry` has the `SkillsRegistry` initializers: `init(stack:variables:watch:)`,
`init(layers:variables:watch:)`, `init(marketplaces:stack:variables:watch:)`. Unlike
`SkillsRegistry`, the build is in `load()`, not in `init`.

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
  agents-demo/              (no mode)       the usage
                            --chat          a Router session with the agents tool;
                                            the lead agent starts two agents
                            --fan-out       a Router session with the agents tool;
                                            two agents at once, one on each slot
                            --watch         an AgentReloadReport on each onReload
                            --marketplace   the marketplace fixture as a source
```

`--chat` and `--fan-out` need a resolved profile; there is no default CLI
mode, because the CLI needs a profile. `--marketplace` reads the fixture
through `file://` folder sources, one for each plugin. The tests use a git
fixture. A production host can mix git and `file://` sources.

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
  answers, the six operations, the mount of each operation, the final
  message as the detail of the background run, the path outside a Router
  session. `agents-demo --chat`. *Needs M2, M3.*
- **M5 — Scheduler and nested runs.** The limit, `cancelRuns(caller:)`,
  `check agent` with no id, `maxRetainedRuns`, `stop()`. The `agents` tool in
  a run, the end of a run when its session is idle, `inherit` from a calling
  run, `maxDepth`, cancel that goes down. `agents-demo --fan-out`.
  *Needs M4.*
- **M6 — Semantics and user surfaces.** `skills:` preload, `disallowedTools`
  and MCP patterns, `Agent(a, b)`, `maxTurns`. `SlashCommandProviding` for
  agents, `AgentsCLI`,
  `--watch`, `--marketplace`. *Needs M4.*
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
  the mount of each op (`start agent` background, the other five
  synchronous, no timeout, no settle period of its own); with a settle period
  of 0, `start agent` answers with the pending envelope, and its `next` sentence tells the model to end its
  answer; the final message is the one terminal of the call, names the agent
  and the run, and holds the full text, also when long; a failed or
  cancelled run gives a `.completed` terminal; `check agent` never waits;
  `cancel agent` of a run that ended names the agent one time; `send agent`
  to a run in operation is answered before the run ends, and to a run that
  ended gives the run-ended corrective; `send caller` comes to the caller as
  mail, and with no caller gives "You have no caller."; `send parent` is
  `send caller`; the mount table of §9.3; `agent.message.sent` never holds
  the text of the message.
- Commands: `/name text` gives `text` as the prompt, unchanged; a
  `user-invocable: false` agent has no command.
- Reload: add, change, remove; a burst gives one final catalog; a run in
  operation is unchanged; the pre-reload tool behavior of §9.1;
  `commandUpdates` after an agent reload.
- Runs: the model match table; a finished run holds no session;
  `maxRetainedRuns`; a parent ends after its child, answers the final
  message of the child as mail, and ends when its session is idle, with the
  reply of its last answer as its result; a parent answers each message of a
  child before it ends; a run with no child ends after the answer of its
  task; `mailDeliveryPaused` ends a run as failed; a failing
  parent cancels its children first; with `maxConcurrentAgents` 2, two waiting siblings
  hold no slot and their children start; with `maxConcurrentAgents` 1, a
  working parent starts one child, and a start by a different caller at that
  time gets the limit corrective; the limit and `maxDepth` corrective answers; a caller
  cannot address another caller's run; `cancelRuns(caller:)`; `stop()`.

**Integration suite** in a nested `IntegrationTests/` package, as in the peer
packages (Swift Testing, `.serialized`, small `mlx-community` models). No
environment variable selects or skips a test: the nested package is the
separation. A root `swift test` does not build it. CI runs it through the
`integration-package-path: IntegrationTests` input of the shared workflow:

- A local file, a git-marketplace plugin (M7), and a `file://` folder each
  become a live sub-agent.
- The flash model reference runs on the flash slot.
- Full circle: the root calls `start agent`, the sub-agent uses a tool, the
  final message comes to the root session as mail, the pump starts an answer
  to it, and `check agent` gives the same text.
- Nested: `agentSpawn` links three sessions; `parentToolCallId` joins to the
  `start agent` call.
- A slash command gives its result. Two slots overlap. `cancel agent` stops a
  run. A live edit is used by the next delegation while an old run completes.

## 16. To verify during implementation

- `ToolContext.completionToken` joins to the tool call in the Router
  transcript, for `AgentSpawn.parentToolCallId`. (M3)
- The detail of a background `start agent` call is its `.completed`
  terminal, and the pump delivers it to the calling session as mail. Confirm
  through an `OperationTool` operation and with a detail longer than 4 096
  characters. (M4)
- A final message that settles while an answer of the calling session is in
  operation waits in the mail, and the pump delivers it after that answer
  ends. It is never lost. (M4, M5)
- `runSettled` is sent for each settled `start agent` call. (M4)
- A final message for a closed session does no harm. (M5)
- Plain-text answers use the Skills method: the operation gives text, the
  wrapper decodes the JSON string that `OperationTool` makes. (M4)
- The Extras layer has the §6.1 shape, for a catalog and for a tree, with
  the partials at `<snapshot>/_partials/`. Confirm with the
  `swissarmyhammer/skills` marketplace. (M7)
- `render(_:at:in:)` with `agents/<id>.md` reaches `<layer root>/_partials/`.
  (M3)
- A `file://` source with `path:` gives the folder unchanged. (M2)
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
