# Plan: FoundationModelsAgents — Claude-style sub-agents for Foundation Models

A Swift package that loads [Claude Code sub-agent](https://code.claude.com/docs/en/sub-agents)
definition files from a stack of directories and marketplaces. It gives them
to Apple's [Foundation Models framework](https://developer.apple.com/videos/play/wwdc2026/241/)
through **one tool**, `agents`. Many agents can run at the same time.

Each agent run drives one session of
[`FoundationModelsRouter`](../FoundationModelsRouter/README.md). The Router
supplies the model, the tool loop, compaction, recording, and the background
run plane. `FoundationModelsExtras` supplies the file stack, the marketplace,
the watcher, and the render. This package supplies only the semantic layer of
agents: the definition, the catalog, the delegation rules, and the tool.

**Primary target: macOS 27, on-device.**

---

## 1. Guiding principles

- **An agent is a tool.** The framework has no agent concept. This package
  adds one fused `OperationTool` named `agents`, with four operations on one
  noun: `list agents`, `start agent`, `check agent`, `cancel agent`. This is
  the same shape as the `Agent` tool in Claude Code. Because it is a tool as
  all others are, an agent can have it, and thus agents can start agents.
- **The minimum semantic layer.** This package owns what is specific to
  agents, and nothing more: the decode of the agent frontmatter, the
  validation, the catalog with identity by `name`, the model match, the tool
  resolution, the runner, and the tool. All file access, all watching, all
  rendering, and all marketplace work are in `FoundationModelsExtras`. This
  is the same boundary that `FoundationModelsSkills` has, and a boundary test
  enforces it (§14).
- **Only shipped sibling APIs.** This plan uses the Router, Extras, and Skills
  APIs as they are. It needs no work in a sibling repository.
- **One session system and one recording system: the Router's.** An agent run
  is a Router session. This package has no session type, no tool loop, no
  compaction, and no recorder.
- **Visibility is the Router's.** All that an agent does is in the transcript
  of its Router session. A user interface shows Router sessions and
  transcripts. This package has no display types and no display contract.
- **All delegation is background, on the Router run plane.** `start agent`
  returns at once with a completion token. The Router tracks the run, tells
  the host when it settles, and gives the result to the calling model in a
  delivery turn. This package does not build a notification mechanism.
- **A sub-agent is a new, isolated session.** It has its own context, its own
  instructions, its own tools, and its own working directory. It sees only
  the task prompt. Only its final text goes back to the caller. The calling
  model has no view into the run. A person who wants the detail reads the
  transcript of the Router session.
- **One run is one task.** A run gets one task prompt, does the task, and
  settles. Its session then closes. There is no follow-up into a settled run.
  A caller that wants more work starts a new run, and puts the necessary
  context into the prompt of that run.
- **Definition, run, and session are different things.** An `AgentDefinition`
  is authored data. An `AgentRun` is one delegated task: the unit of
  scheduling and cancellation. A run drives one Router session and does not
  give that session to other code.
- **The description is the delegation contract.** Agent catalogs are small.
  The `name` and `description` of each agent go directly into the tool
  description. The calling model reads them to decide when to delegate. There
  is no search operation.
- **The Router decides which models exist.** The `model` value of a
  definition must match a model that the resolved Router profile makes
  available: a slot name or a model reference. This package has no model
  names and no alias table of its own.
- **Parallel by admission, and honest about the GPU.** A FIFO admission gate
  limits how many runs have a turn in operation at one time. The Router
  serializes generation on each resident model. Runs on different slots
  overlap. Runs on the same slot take turns.

## 2. Architecture

```
┌─ Layer 3  FM adapter ───────────────────────────────────────────────────┐
│  AgentsTool    one OperationTool "agents": four operations, one noun    │
│  AgentRunner   actor: admission, the run index, the token → run map     │
│  AgentRun      drives ONE RoutedSession; state and result               │
├─ Layer 2  AgentRegistry ────────────────────────────────────────────────┤
│  the cached catalog of `agents/**/*.md` over the local and marketplace  │
│  layers; identity by `name`; rebuilt on a watch or a marketplace update │
├─ Layer 1  AgentDefinition ──────────────────────────────────────────────┤
│  AgentFrontmatter.decode + validation of one located document           │
└─────────────────────────────────────────────────────────────────────────┘
  Extras:       DotfolderStack · FrontmatterDocumentStack · DotfolderWatcher
                StenciledDotfolderStack · QuarantinedText · AgentsMd
                Operations (OperationTool, @Operation, OperationResolver)
  Marketplace:  MarketplaceLayerProviding · MarketplaceLayer · MarketplaceStore
  Router:       LanguageModelProfile slots · RoutedSession · run plane
                (ToolContext, BackgroundTool) · recording
  Skills:       SkillsRegistry
```

- **Layers 1 and 2 have no model.** They are files and validation only. They
  keep the `model` value as text. The runner matches it against the Router
  profile (§6).
- **The host makes the dependencies and gives them to the constructors.**
  - The host makes the `DotfolderStack` and, when it uses marketplaces, a
    `MarketplaceLayerProviding` (usually a `MarketplaceStore`). It gives them
    to `AgentRegistry.init`.
  - The host makes the `Router` and resolves a `LanguageModelProfile`.
  - The host makes the `SkillsRegistry`.
  - The host gives the profile and the skills registry to
    `AgentEnvironment.init`.

  These parameters are necessary and have no default values. This package
  never makes a `DotfolderStack`, a `MarketplaceStore`, a `Router`, or a
  `SkillsRegistry`, and never resolves a profile. Thus the host controls the
  file locations, the marketplace sources, the model selection, the recording
  location, the skill locations, and the lifetime of each dependency. The
  root session of the host and the sub-agents use the same instances.
- **The Router comes in at one point:** `AgentEnvironment.profile`. The
  profile is the Router object that this package needs: `makeSession` is on
  `profile.standard` and `profile.flash`, and the profile keeps its models
  resident.

## 3. Identity, locations and precedence

- **The layers.** The registry reads one combined view of all the layers,
  lowest to highest precedence:

  ```
  marketplace[0] < … < marketplace[n] < defaults < user < project
  ```

  The local layers come from the host's `DotfolderStack`: `defaults`, `user`
  (`~/.config/<name>/`), `project` (`<workingDirectory>/.<name>/`). The
  marketplace layers come from `MarketplaceLayerProviding.marketplaceLayers()`,
  and the registry puts them below all the local layers. This is the rule of
  the Extras marketplace and of `SkillsRegistry`. A host that wants Claude's
  own directories appends local layers, for example a layer with the root
  `~/.claude`.
- **Agent files are the `.md` files at all depths below `agents/` in the
  combined view.** One call gives them: `tree("agents")`. Subdirectories
  organize files. They do not make namespaces.
- **Which marketplace layers hold agents** is in §10.
- **Override of a file is the rule of the stack.** The unit of override is
  the file path. For a path relative to a layer root, the copy in the highest
  layer wins, and each lower copy is hidden. `agents/review/security.md` in
  the project layer replaces the same path in a marketplace layer. A
  directory is never replaced: it holds the union of the names of all the
  layers.
- **The `name` frontmatter key is the identity** (the Claude rule). The file
  name and the path do not have to match it. A valid name has lowercase
  letters, digits, and hyphens.
- **Two winning files with the same `name`.** When the files are in different
  layers, the file in the higher layer wins (the Claude rule: project over
  user; each local layer over each marketplace). When the files are in the
  same layer, the last path in a stable sort order wins, and the catalog has
  a diagnostic. This is the same as the Claude `/doctor` duplicate report.
- **Provenance.** Each definition keeps its URL and its layer. A definition
  from a marketplace layer also keeps its `MarketplaceProvenance` (the id,
  the URL, the commit). `AgentListing` and each diagnostic show it.
- **The catalog is cached and rebuilt (the Skills pattern).** The registry
  builds an `AgentCatalog` value and holds it. `catalog()` gives the current
  value and does no file I/O. The registry builds a new catalog and replaces
  the old one atomically when one of these occurs:
  - `DotfolderWatcher` reports a change in a local layer, or in a marketplace
    layer that has `isWatchable == true`.
  - The marketplace provider reports `layerUpdates`.

  `onReload` publishes each new catalog. A host that gives `watch: false` and
  no marketplace provider gets a catalog that it rebuilds with `reload()`.

## 4. Definition format — a Claude-compatible subset

One `.md` file has YAML frontmatter and a body. The body is the system prompt
of the sub-agent.

```markdown
---
name: code-reviewer
description: Reviews code for quality and best practices. Use proactively after changes.
tools: Read, Grep
model: flash
---

You are a code reviewer. When invoked, analyze the code and provide
specific, actionable feedback on quality, security, and best practices.
```

**The load is split, decode, validate. The render is later, at the start of
a run.** This is the order of `SkillsRegistry`.

1. **Split and decode, on the raw text.** The registry reads each file
   through a `FrontmatterDocumentStack` on the plain `DotfolderStack` of all
   the layers, with `AgentFrontmatter.decode`:

   ```swift
   let documents = FrontmatterDocumentStack(
     base: DotfolderStack(layers: marketplaceLayers + stack.layers),
     decode: AgentFrontmatter.decode,            // this package's schema, with Yams
     onDiagnostic: collect)
   let files = documents.tree("agents")          // [path: Located<FrontmatterDocument<AgentFrontmatter>>]
   ```

   The frontmatter is never rendered. A `{{ }}` in a frontmatter value is
   text.
2. **Validate.** `AgentDefinition.init` takes one located document. It keeps
   the URL, the layer, and the marketplace provenance. An error names the
   file, the layer, and the key.
3. **Render the body at the start of a run (§7).** The run renders the body
   with `StenciledDotfolderStack.render(_:in:)`, on the winning layer of the
   definition, with the host's `variables` and `partialLocations`. The trust
   comes from the layer: a file of the `defaults` layer renders trusted, and
   a file of each other layer, which includes each marketplace layer, renders
   untrusted. An `{% include %}` finds a partial in the scope that Extras
   gives the layer: a marketplace document sees its own marketplace and the
   local layers; a local document sees the local layers only. There is no
   argument substitution and no shell injection. The dynamic input of a run
   is the task prompt, which is not rendered.

Failures:

| Failure | Source | Result |
|---|---|---|
| The frontmatter does not decode | `FrontmatterDocumentStack` | `metadata == nil`. One catalog diagnostic. No definition. |
| The `.md` file has no frontmatter block | this package | `metadata == nil`. One catalog diagnostic. No definition. |
| A value is not valid | this package | One catalog diagnostic for each value. No definition if `name` or `description` is not valid. |
| The body does not render | `StenciledDotfolderStack` | The run fails with `bodyRenderFailed`, before it makes a session. |

A bad file does not stop a good file next to it.

Field tiers: parse all fields, act on tier 1, keep tier 2 as data, report
tier 3.

| Tier | Fields | Behavior |
|---|---|---|
| **1 — enforced** | `name`, `description` (required); `tools`, `disallowedTools`; `model`; `skills`; `maxTurns`; `compactionPrompt` (ours) | Full semantics (§5–§7) |
| **2 — data only** | `color`; `background`; all keys that are not known | Available on `AgentListing` for hosts. No behavior. `background: false` cannot be obeyed and gets a diagnostic, because all runs are background runs. |
| **3 — not supported** | `permissionMode`, `mcpServers`, `hooks`, `memory`, `effort`, `isolation`, `initialPrompt` | Parsed, reported as a diagnostic, and ignored. A file written for Claude Code loads. |

`compactionPrompt` is the text of the fold prompt for this agent. A
researcher folds its context differently from a reviewer. When the key is
absent, the run uses `CompactionPrompt.default`.

## 5. Tools and skills for a sub-agent

- **`ToolCatalog`.** The host registers the available tools by name:
  `name → factory of any FoundationModels.Tool`. Each run gets new instances.
  The `skills` tool from FoundationModelsSkills is one more catalog entry.
- **Resolution (Claude semantics).** When `tools` is absent, the agent gets
  the full catalog. `disallowedTools` is applied first. Then `tools` is
  resolved against the remainder. A tool named in the two lists is removed.
  The MCP patterns `mcp__<server>`, `mcp__<server>__*`, and `mcp__*` are
  prefix matches against catalog names. An unknown tool name gets a
  diagnostic and is skipped. An unknown name in `disallowedTools` gets an
  **error-level** diagnostic, because a dropped deny gives more access than
  the author wanted.
- **Agents can start agents.** The `agents` tool is a tool as all others are.
  The runner supplies it under the catalog name `agents`, so the rules above
  apply to it: a definition with no `tools` key gets it, `tools` can list it,
  and `disallowedTools` can remove it. An `Agent(a, b)` entry (the Claude
  form) gives the `agents` tool with `start agent` limited to the agents `a`
  and `b`. Each run gets its own tool instance from `AgentsTool.make`. The
  lineage (§7.2) records each level, and `AgentEnvironment.maxDepth` stops
  recursion with no end (§8.3).
- **The host makes the `SkillsRegistry` and gives it to this package.**
  `AgentEnvironment.init` has a `skills: SkillsRegistry` parameter. It is
  necessary, and it has no default value. This package never makes a
  `SkillsRegistry`: it does not select skill locations, a render policy, or a
  watch mode. The host makes one registry, usually with the same
  `DotfolderStack` that it gives to the `AgentRegistry`, and uses that one
  instance for the environment and for the `skills` tool in the
  `ToolCatalog`. A host that has no skills gives a registry with no roots.
- **`skills:` preload.** At the start of a run, `SkillsRegistry.call(id:)` on
  the registry of the environment gives the rendered body of each listed
  skill, and the run appends it to the instructions. A skill that is unknown
  gets a diagnostic and is skipped. A skill with `isModelVisible == false`
  gets a diagnostic and is skipped.
- **`maxTurns`.** The Router runs the tool loop in one turn. Thus the limit is
  enforced on tool calls: each tool that the run receives has a counting
  decorator. When the count goes above `maxTurns`, the run cancels the turn
  and fails with `hitMaxTurns`. The failure contains the partial text.
  *Divergence:* Claude counts agentic turns and stops silently. This package
  counts tool calls, which is a tighter limit, and reports a failure.

## 6. Model selection — frontmatter to a Router model

The `model:` value must match a model that the Router makes available. A
resolved `LanguageModelProfile` makes two language models available:
`profile.standard` and `profile.flash`. Each one has a `chosen: ModelRef`.
This package has no model names and no alias table of its own.

| `model:` value | Result |
|---|---|
| absent / `inherit` | the slot of the caller (see below) |
| a slot name: `standard` or `flash` (the `ModelSlot` raw values) | that slot |
| a model reference equal to the `chosen.stringValue` of a slot, or to its repository part (the text before `@`) | that slot |
| all other values | a diagnostic, then `inherit` |

- **The slot of the caller.** When an agent run started this run, the runner
  knows the slot of that run from its index, and `inherit` gives that slot.
  When a host session or host code started this run, `inherit` gives
  `AgentEnvironment.defaultSlot` (default `.standard`). The host knows the
  slot of its session and sets `defaultSlot` to agree with it.
- When the two slots have the same chosen model, a model reference matches
  `standard`.
- `embedding` is a Router slot but not a language model. It gets the
  diagnostic.
- The Claude aliases (`opus`, `sonnet`, `haiku`, `fable`) are not Router
  models. A file written for Claude Code loads, gets the diagnostic, and runs
  on the `inherit` slot.
- **The match needs the profile, so the runner does it.** Layer 1 checks only
  that `model` is a non-empty string. `runner.catalog()` takes the current
  registry catalog and applies the match: each listing entry gets its slot
  and its model reference, and each value with no match adds a diagnostic. A
  run matches again when it starts.
- `list agents` gives the listing of `runner.catalog()`, so the calling model
  sees which Router model an agent uses.

*Divergence:* Claude also obeys a `CLAUDE_CODE_SUBAGENT_MODEL` environment
variable and a `model` parameter on its Agent tool. This package has neither.

## 7. Execution — one run drives one Router session

An `AgentRun` does these steps:

1. **Resolve** the definition: `registry.catalog().definition(named:)`. The
   run keeps that definition for its full life. A later catalog does not
   change a run.
2. **Render the body** (§4, step 3). A failure fails the run.
3. **Assemble instructions**, in this order: the `AgentsMd.documents(from:)`
   texts for the run's working directory (outermost first), the rendered
   body, the rendered `skills:` bodies.
4. **Resolve tools** (§5) and put the counting decorator on each one.
5. **Match the model** (§6), then **make the session** on the slot handle:

   ```swift
   let model = slot == .flash ? profile.flash : profile.standard
   let session = model.makeSession(
     instructions: instructions,
     workingDirectory: workingDirectory,
     tools: tools,
     budget: environment.budget(model.contextTokens),   // TokenBudget
     compactionPrompt: definition.compactionPrompt ?? .default,
     agentSpawn: spawn                                   // §7.2; nil for a host-driven run
   )
   ```

6. **Wait for admission** (§8.3), then drive one turn with
   `session.streamEvents(to: prompt)`. The run reads the events of the turn
   for two functions: the final text, and the progress posts (§8.2).
7. **Wait for its own delegates.** When the turn started agent runs, the run
   gives back its admission and waits for `runSettled` from its session. It
   then gets admission again and drives the delivery turn with
   `dispatchNextPrompt()`. It does this again until its session has no open
   background run.
8. **Settle.** The final text of the last turn is the result of the run. The
   run closes its session.

The Router gives each session automatic compaction, recovery from a context
overflow in the middle of a turn, the tool output limit
(`TokenBudget.toolOutputLimit`), correlated tool events, and the recording.
`environment.budget` is a function from the context size of the model to a
`TokenBudget`. The default is `TokenBudget(limit: contextTokens)`.

**Working directory.** The default is `AgentEnvironment.workingDirectory`, so
that a sub-agent works on the same project as its caller and reads the same
`AGENTS.md` files. A host-driven run can give a different directory.

*Divergence:* Claude also puts a git-status snapshot and its memory hierarchy
into the first context of a sub-agent. This package gives a run only the
`AGENTS.md` texts, the body, the skills, and the task prompt. Claude can also
resume a sub-agent with a follow-up prompt. This package cannot: one run is
one task.

### 7.1 The object model

```
AgentDefinition  (authored file)   static data; one for each name
      │  runner.start(name, prompt)
      ▼
AgentRun  (id = session id)        ONE delegated task: scheduling and cancel
      │  drives; does not vend
      ▼
RoutedSession  (Router)            the engine of the run; made and closed with the run
```

- **One definition, many runs.** Runs of the same agent are independent. Each
  has its own session, context, and recording.
- **`AgentRun.id` is the id of its session.** It is also the name of the
  recording directory of the run.
- **A run holds its session and does not vend it.** The task prompt goes in
  through the run. The final text comes out through the run.
- **Residency is the Router's.** A session retains its profile, so a resident
  model is not evicted during a run.
- **The session lives as long as the task.** The run makes the session when
  it starts, and closes it when it settles. A settled run holds no session
  and no model context.
- **The record of a settled run stays for `check agent`.** The record is
  small: the id, the agent name, the state, and the final text.
  `AgentEnvironment.maxRetainedRuns` removes the oldest settled records. The
  id of a removed record gives a clear `gone` answer.

### 7.2 Lineage

A tool call in a Router session can read `ToolContext.current`. `start agent`
reads the caller from it and records the lineage in the session creation
metadata:

```swift
let context = ToolContext.current   // nil outside a Router session
let spawn = context.map {
  SessionSidecar.AgentSpawn(parentSessionId: $0.sessionID,
                            parentToolCallId: $0.completionToken)
}
```

- The session of a sub-agent is a **root session** of the Router
  (`parentId == nil`). Its recording directory is
  `<recordingsDir>/<routerId>/<sessionId>/`, beside the directory of its
  caller.
- The Router writes `agentSpawn` into `session.json` and onto the `.session`
  event of the transcript. The `.session` event is written when the first
  turn starts.
- A host-driven run has no caller. Its `agentSpawn` is `nil`.
- The agent `name` is in the transcript of the caller: it is an argument of
  the `start agent` tool call that `parentToolCallId` points to.
- The caller can be a host session or the session of an agent run. The rule
  is the same, so the `agentSpawn` values make a chain through all levels.

The Router record is thus sufficient to show which session started which
agent. This package adds no lineage data of its own.

## 8. Delegation — the `agents` tool and the scheduler

### 8.1 The operations

`AgentsTool.make(context:)` builds an `OperationTool<AgentsToolContext>` named
`agents` from `@Generable @Operation` structs. `make` reads the catalog one
time: the tool description contains the `name` and `description` of each
agent at that time. A host makes a new tool for each new calling session. The
runner makes a new tool for each run that gets the `agents` tool.

**The `name` parameter is a string. The schema does not pin it to a list of
names.** Each operation reads `runner.catalog()` when the call occurs, and
that is the current catalog of the registry. `start agent` checks the name
against it. The context can limit the names (the `Agent(a, b)` form, §5);
`start agent` also does that check when the call occurs. Thus a reload is
visible to a session that is in operation:

- A changed agent: the next `start agent` uses the new definition.
- A removed agent: `start agent` gives a corrective answer that contains the
  current listing.
- An added agent: it is not in the tool description, because the description
  is the catalog from the time of `make`. `list agents` shows it, and
  `start agent` accepts its name. The tool description tells the model that
  `list agents` gives the current catalog.

A `name` addresses a definition. An `id` addresses a run: it is the
completion token that `start agent` returned.

| op | parameters | result |
|---|---|---|
| `list agents` | — | `[AgentListing]`: `name`, `description`, `slot`, `model`, `color`, `source`, from `runner.catalog()` at the time of the call (§6). `source` is the layer, and the marketplace id for a marketplace layer. |
| `start agent` | `name`, `prompt` | A `PendingRunEnvelope`: `pending`, `completionToken`, `next`. The run continues in the background. An unknown `name`, a `name` that the context does not permit, or a depth above `maxDepth` gives a corrective answer and starts no run. |
| `check agent` | `id?`, `seconds?` | `AgentStatus`: `id`, `name`, `state`, `lastEvent`, and the **full** final text when the state is `finished`. When `id` is absent, one status for each run of this caller that is in the index. `seconds` (default 0) is how long to wait for the run to settle. |
| `cancel agent` | `id` | The `CancelOutcome` of the run, as `AgentStatus`. |

All results are `Encodable` values. `OperationTool` gives them to the model as
JSON text. A removed or unknown `id` gives `state: gone`. A caller can
address only the runs that it started.

The resolver adds these verb aliases: `stop` → `cancel`, `run` → `start`,
`status` → `check`.

`OperationCLIDriver(tool:)` gives the same four operations as a command line.

### 8.2 Background runs on the Router run plane

`start agent` does not do the work in its own call. It mounts an internal
tool, `AgentRunTool`, with `ToolContext.current.mount(_:op:as:)` in the
`.background` mode, and calls it.

- `AgentRunTool` conforms to `BackgroundTool`. Its `runKind` is `.swiftTask`.
  Its `collectInstruction(forCompletionToken:)` tells the model to end its
  turn and to use `check agent` with that token. Its
  `canceler(forCompletionToken:)` calls `session.cancelCurrentTurn()` on the
  run's session and reports `.cancelled`.
- The Router returns the `PendingRunEnvelope` at once. The body of the run
  continues: admission, the turn, the delegates of the run, the result.
- **One run, one token.** The completion token of the background run is the
  `id` that the model uses. The runner maps the token to the run.
- **Progress.** The body posts `ToolContext.progress(_:)` for each tool call
  and each recorded entry of the sub-agent, and at a fixed interval while it
  waits for admission or for its delegates. The idle timeout of the mount
  (`AgentEnvironment.idleTimeout`) thus means "no activity", not "total
  time".
- **Settlement.** The terminal event of the run contains the final text as
  its `detail`. The Router cuts the detail to the last
  `ToolContext.terminalDetailTailLimit` characters. `check agent` returns the
  full text from the record of the run.
- **Notification is the Router's.** When the run settles, the host receives
  `SessionEvent.runSettled`. The calling model receives the result in a
  delivery turn: `respond(to:)` drains the run plane after its own turn, and
  `dispatchNextPrompt()` runs the delivery turn for a host that drives
  `streamEvents(to:)`. An agent run is such a host for its own session (§7,
  step 7).
- **`check agent`** calls `ToolContext.wait(completionToken:seconds:)`.
  **`cancel agent`** calls `ToolContext.cancel(completionToken:)`.
- **Close.** `close()` on the calling session sweeps its mailbox, and the
  sweep runs the canceler of each open run. The cancel of a run thus goes
  down to the runs that it started.

**Outside a Router session** `ToolContext.current` is `nil`. This is the case
for a native `LanguageModelSession` and for the command line. The operations
then use the runner directly. `start agent` returns an envelope whose token
is the run id. There is no delivery turn, and the model uses `check agent`.

### 8.3 `AgentRunner` — admission and the index

`AgentRunner` is an actor. It owns each `AgentRun`. It is not a session
system, a tool loop, a recorder, a notifier, or a display model.

- **Admission.** At most `maxConcurrentAgents` runs have a turn in operation.
  More runs wait in a FIFO queue. The Router has no admission gate for
  sessions. The Router's generation gate, one for each resident model,
  serializes the generation calls below this gate.
- **A run holds admission only during a turn.** A run that waits for its
  delegates holds no admission (§7, step 7). Thus a parent cannot block its
  children, and a full gate of parents cannot stop all work.
- **Depth.** A run that a host session or host code started has depth 1. A
  run that an agent run started has the depth of that run plus 1. The runner
  finds the depth from the caller in its index. `AgentEnvironment.maxDepth`
  (default 3) is the limit. `start agent` above the limit gives a corrective
  answer and starts no run.
- **The index.** `runs`, `run(id:)`, the token → run map, and, for each run,
  its caller (`ToolContext.sessionID`, or `nil`), its slot, and its depth.
  The index holds the runs in operation and the records of the settled runs
  (§7.1). It is for program control: to find, check, and cancel runs.
- **`runner.catalog()`**: the current registry catalog with the model match
  (§6).
- **Host-driven fan-out** needs no calling session:

  ```swift
  async let a = runner.start("code-reviewer", prompt: p1).result()
  async let b = runner.start("test-writer",   prompt: p2).result()
  ```

- **Cancellation is structured.** `run.cancel()` cancels the turn of the run
  and the open runs that it started. When the runner stops, it cancels all
  runs and closes all sessions.
- **One runner holds one profile.** A host that uses two profiles makes two
  runners.

## 9. Recording and diagnostics

- **Recording is the Router's.** Each run has `transcript.jsonl` and
  `session.json` in its session directory. `Router(recordingsDir:recorder:
  recordingLevel:redact:)` controls the location, the level, and the
  redaction. This package writes no recording files.
- **Visibility is the Router's.** A host that shows agent work shows Router
  sessions and transcripts. The lineage in §7.2 connects the session of a
  sub-agent to the tool call that started it. This package has no observable
  display types, no transcript browser, no transcript index, and no tree
  builder.
- **Diagnostics are data, and they belong to one catalog.**
  `AgentCatalog.diagnostics` is `[AgentDiagnostic]` for the build of that
  catalog. Each one has a severity, a file URL, a layer, a message, and the
  marketplace provenance when the layer is a marketplace layer. The sources
  are: the decode failures that `FrontmatterDocumentStack` gives to its
  `onDiagnostic` hook, and the checks of this package: no frontmatter block,
  a value that is not valid, a duplicate name in one layer, a field that is
  not supported, an unknown tool or skill. `runner.catalog()` adds the
  `model` values that match no model of the Router profile (§6).
- **Marketplace diagnostics stay with the marketplace.** A fetch failure, a
  blocked source, or a snapshot limit is a `MarketplaceDiagnostic` or a
  `MarketplaceEvent` of the host's `MarketplaceStore`. This package does not
  copy them.

## 10. Dependencies and marketplaces

| Package | Products | Used for |
|---|---|---|
| `FoundationModelsRouter` | `FoundationModelsRouter` | `LanguageModelProfile`, `ModelSlot`, `ModelRef`, `RoutedSession`, `SessionEvent`, `ToolContext`, `BackgroundTool`, `ToolMount`, `TokenBudget`, `CompactionPrompt`, `SessionSidecar.AgentSpawn` |
| `FoundationModelsExtras` | `FoundationModelsExtras`, `Marketplace`, `Operations`, `OperationsCLI` | `DotfolderStack`, `FrontmatterDocumentStack`, `FrontmatterDocument`, `Located`, `DotfolderWatcher`, `StenciledDotfolderStack`, `QuarantinedText`, `AgentsMd`; `MarketplaceLayerProviding`, `MarketplaceLayer`, `MarketplaceProvenance`; `OperationTool`, `@Operation`, `OperationResolver`; `OperationCLIDriver` |
| `FoundationModelsSkills` | `FoundationModelsSkills` | `SkillsRegistry` for the `skills:` preload |
| Yams, ULID.swift | | `AgentFrontmatter.decode`; ids |

All the sibling APIs in this plan are shipped. There is no prerequisite work
in a sibling repository.

Packaging: one SwiftPM library target, `FoundationModelsAgents`. The
`./Examples` executables are targets in the same package. Sibling packages are
remote dependencies on the `main` branch, not `path:` dependencies. Swift
tools 6.2. `.macOS("27.0")`. There is no fallback for earlier systems.

**Marketplaces of agents, with the shipped `Marketplace` product.**

- **The registry takes any `MarketplaceLayerProviding`.** It reads
  `tree("agents")` in each marketplace layer, as it reads a local layer. It
  does not know how the layer was made.
- **A `file://` source with `path:` holds agents.** `MarketplaceStore` uses
  that folder as the layer root, unchanged, with no resolver and no
  snapshot. A folder that holds `agents/**/*.md` thus gives agents. This is
  the supported way to share agents through a marketplace: a team puts its
  agents in a folder or a checkout, and the host names that folder as a
  source.
- **A git source holds no agents.** For a git source, the shipped resolver
  and snapshot writer copy only the entry folders of the layout (a folder
  that holds `documentName`, for example `SKILL.md`), the plugin `skills`
  folders, and the partials. They do not copy an `agents/` folder. A layer
  from a git source thus has no `agents/` folder, and gives no agents. This
  is not an error: the registry reads an empty tree.
- **One store or two.** A `file://` source with `path:` does not use the
  layout, so the host can give the same store to `SkillsRegistry` and to
  `AgentRegistry`. The skills registry reads `<id>/SKILL.md` at each layer
  root, and the agents registry reads `agents/` below each layer root.

**Naming.** `FoundationModelsSkills` brings in `FoundationModelsRanker` and
`FoundationModelsMetadataRegistry`, which export a protocol named
`AgentSession` for their selection step. It is not related to sub-agents. The
public nouns of this package are `AgentDefinition`, `AgentRegistry`,
`AgentRun`, `AgentRunner`, and `AgentsTool`. This package does not use the
name `AgentSession`.

## 11. Public API sketch

```swift
// The host makes the dependencies. This package makes none of them.
let stack   = DotfolderStack(name: "myapp", workingDirectory: projectURL)
let market  = MarketplaceStore(
  sources: [MarketplaceSource("file:///Users/me/team-agents", path: ".")],
  layout: SkillMarketplaceLayout.skills)       // a file:// source with path: does not use it
let router  = Router(recordingsDir: recordingsURL)
let profile = try await router.resolve(profile: coding, reporting: progress)
let skills  = SkillsRegistry(marketplaces: market, stack: stack, watch: true)

// Layers 1 and 2: the cached catalog of `agents/**/*.md`. No Router here.
let agents = AgentRegistry(
  marketplaces: market,                        // optional; any MarketplaceLayerProviding
  stack: stack,
  variables: ["project": "acme"],              // for the body render
  watch: true)
await market.start()
agents.catalog().listing                       // [AgentListing]
agents.catalog().definition(named: "code-reviewer")
agents.catalog().diagnostics                   // [AgentDiagnostic]
for await catalog in agents.onReload { … }     // each rebuilt catalog

// One `skills` instance: for the `skills:` preload, and for the `skills` tool.
let skillsTool = try await SkillsTool.make(registry: skills)
var tools = ToolCatalog()
tools.register("skills") { skillsTool }

let env = AgentEnvironment(
  profile: profile,                            // necessary; from the host's Router
  skills: skills,                              // necessary; from the host
  workingDirectory: projectURL,
  tools: tools,
  defaultSlot: .standard,
  maxConcurrentAgents: 4,
  maxDepth: 3
)
let runner = AgentRunner(registry: agents, environment: env)
await runner.catalog().diagnostics             // with the `model` match

// Host-driven runs.
let run    = try await runner.start("code-reviewer", prompt: "Review:\n\(diff)")
let report = try await run.result()

// Model-driven delegation from a Router session.
let agentsTool = try await AgentsTool.make(context: AgentsToolContext(runner: runner))
let root = profile.standard.makeSession(
  instructions: "…",
  workingDirectory: projectURL,
  tools: [agentsTool] + otherTools
)
for try await event in root.streamEvents(to: userPrompt) {
  // .runSettled tells the host that an agent run settled
}
```

`AgentRegistry` has the same initializer shapes as `SkillsRegistry`:
`init(stack:variables:watch:)`, `init(layers:variables:watch:)`, and
`init(marketplaces:stack:variables:watch:)`.

Core types: `AgentFrontmatter`, `AgentDefinition`, `AgentListing`,
`AgentRegistry`, `AgentCatalog`, `AgentDiagnostic`, `AgentEnvironment`,
`ToolCatalog`, `AgentsTool`, `AgentsToolContext`, `AgentStatus`,
`AgentRunner`, `AgentRun` (`id`, `agent`, `caller`, `depth`, `state`,
`recordingDirectory`, `result()`, `cancel()`), `AgentRunState` (`queued`,
`running`, `finished(String)`, `failed(AgentRunFailure)`, `cancelled`),
`AgentRunFailure` (`bodyRenderFailed`, `hitMaxTurns`, …).

## 12. Examples — `./Examples`

Examples are part of the deliverable. They are executable targets in the root
package, so one `swift build` builds the library and the examples.

```
Examples/
  defaults/            the `defaults` layer of the example stack
    agents/
      code-reviewer.md     flash slot; tools: Read, Grep
      test-writer.md       standard slot
      lead.md              tools: Agent(code-reviewer, test-writer)
    _partials/
      house-rules.md       included by the agents
  marketplace/         a folder used as a `file://` marketplace source
    agents/
      security-reviewer.md
  DelegateCLI/         model-driven delegation from a Router session: start
                       agent, the delivery turn, check agent. The `lead`
                       agent starts the two other agents. Ends with a live
                       edit: put a project copy of agents/code-reviewer.md
                       in place during operation, and the next run uses it.
  FanOut/              host-driven parallel runs on the two slots. Prints
                       which runs overlap and which runs take turns.
```

Each example is small and has one purpose. `DelegateCLI` comes with M4 and
gets the `lead` agent and the marketplace folder with M5. `FanOut` comes with
M5.

## 13. Milestones

- **M1 — `AgentDefinition`.** `AgentFrontmatter.decode` with Yams. The
  validation of one `Located<FrontmatterDocument<AgentFrontmatter>>`: field
  tiers, name validation, tool-list parsing. Errors with a file, a layer, and
  a key. Hermetic tests with `Located` fixtures.
- **M2 — `AgentRegistry`.** The layer plan (marketplace layers below the local
  layers), the read through `FrontmatterDocumentStack` and `tree("agents")`,
  identity by `name`, the same-name rules, provenance, `AgentCatalog`, the
  catalog cache with atomic replacement, the rebuild from `DotfolderWatcher`
  and from `layerUpdates`, `onReload`, `reload()`. The boundary test (§14).
  Tests with `MarketplaceFixtures`. *Needs M1.*
- **M3 — `AgentRun`.** One run from start to end on a Router session: the body
  render on the winning layer; instructions from `AgentsMd`, body and skills;
  tool resolution; the model match against the Router profile (§6) and
  `runner.catalog()`; the budget and the fold prompt; `agentSpawn`; the final
  text; the close of the session at settlement. `run.cancel`. *Needs M1.*
- **M4 — `AgentsTool`.** The fused `OperationTool`. `list agents`,
  `start agent`, `check agent` on the Router run plane: the pending envelope,
  lineage, progress posts, settlement, the delivery turn. The path for a
  caller outside a Router session. `DelegateCLI`. *Needs M2 and M3.*
- **M5 — Scheduler and nested runs.** The admission gate, `cancel agent`,
  `check agent` with no id, the records of settled runs and
  `maxRetainedRuns`, runner stop. Nested runs: the `agents` tool in the tool
  set of a run, the wait for delegates with no admission held, `inherit` from
  a calling run, `maxDepth`, cancel that goes down to the started runs.
  `FanOut`. *Needs M4.*
- **M6 — Semantics.** `skills:` preload, the `disallowedTools` order and the
  MCP patterns, the `Agent(a, b)` limit, the `maxTurns` decorator, the idle
  timeout. *Needs M4.*
- **M7 — Finish.** The diagnostics surface, DocC, a README for the package
  and for each example, a document on marketplaces of agents (§10). *Needs
  M5 and M6.*

## 14. Testing

**The boundary test.** One test scans each Swift file under
`Sources/FoundationModelsAgents/`, comments included, and fails on each name
that belongs to Extras. It uses the list of the Skills `LoadingBoundaryTests`:
`FileManager`, `FileHandle`, `String(contentsOf`, `Data(contentsOf`,
`resourceValues`, `contentsOfDirectory`, `DispatchSource`, `O_EVTONLY`,
`resolvingSymlinksInPath`, `FrontmatterDocument.split`, `TemplateEngine`,
`TemplateContext`, `TemplateValue`, `WellKnownValues`, `import Stencil`,
`import libgit2`. Each forbidden name has the reason: the Extras type that
owns that work.

**Hermetic unit tests**, for each milestone: frontmatter tiers, identity and
precedence, tool-list resolution, the model match, the `maxTurns` decorator,
admission and cancellation. They use fixture directory stacks,
`MarketplaceFixtures`, and the Router's test-support sessions. They use no
real model.

**The layer rules are a tested case.** With fixture layers and a fixture
marketplace provider:
- A project copy of a path replaces the marketplace copy of that path.
- A new path adds an agent.
- The same `name` in a marketplace layer and a local layer gives the local
  layer.
- The same `name` two times in one layer gives the last path and one
  diagnostic.
- A definition from a marketplace layer has its provenance in the listing.
- A marketplace layer with no `agents/` folder gives no agents and no
  diagnostic.
- A `{{ }}` in the frontmatter stays as text.
- The body of a `defaults` file renders trusted, and the body of a user,
  project, or marketplace file renders untrusted.
- A marketplace body can include a partial of its own marketplace. A local
  body cannot include a partial that only a marketplace has, and the run
  fails with `bodyRenderFailed`.
- A decode failure and a `.md` file with no frontmatter each give one
  diagnostic and no definition, and the good files next to them load.

**Reload is a tested case.** Add, change, and remove a definition on disk.
The watcher rebuilds the catalog, and `onReload` publishes it. A
`layerUpdates` event from the fixture provider rebuilds the catalog. A burst
of edits gives one consistent final catalog. A run in operation is not
changed. For a tool that was made before the reload (§8.1): `start agent` of
a changed name uses the new definition; `start agent` of a removed name gives
the corrective answer with the new listing; `list agents` shows an added
name, and `start agent` of that name starts a run, although the tool
description does not contain it.

**The model match is a tested case.** A slot name gives that slot. The chosen
model reference of a slot gives that slot, with and without the revision. A
Claude alias, `embedding`, and an unknown model reference each give a
diagnostic and the `inherit` slot. `inherit` from a calling run gives the
slot of that run.

**The life of a run is a tested case.** A settled run holds no session.
`check agent` gives the full final text from the record. When the number of
settled records goes above `maxRetainedRuns`, the oldest record is removed,
and its id gives `state: gone`.

**Nested runs are a tested case.** With `maxConcurrentAgents` equal to 1, a
parent run that started a child run does not block it: the child gets
admission while the parent waits. `start agent` above `maxDepth` starts no
run. The cancel of a parent cancels its open children. A caller cannot
address a run that a different caller started.

**A real-model integration suite** is in a nested `IntegrationTests/` package
(the family pattern: Swift Testing, `.serialized`, enabled by an environment
variable, small `mlx-community` models). It proves these cases:

- A definition file becomes a live sub-agent.
- A definition from a `file://` marketplace folder, through a real
  `MarketplaceStore`, becomes a live sub-agent.
- A definition with the model reference of the flash slot runs on the flash
  slot.
- Background delegation goes full circle: the root model calls `start agent`,
  the sub-agent uses a tool, the run settles, the host receives `runSettled`,
  the delivery turn gives the result to the root model, and `check agent`
  gives the full text.
- An agent starts a second agent. The inner run settles, the outer run gets
  the result in a delivery turn, and the result of the outer run contains
  it. The `agentSpawn` values link the three sessions.
- The recording of the sub-agent has the `agentSpawn` of its caller, and
  `parentToolCallId` joins to the `start agent` tool call in the transcript
  of the caller.
- The transcript of the sub-agent's Router session contains its tool calls.
- Two runs on different slots make progress independently.
- `cancel agent` stops a run.
- A live edit, end to end: an edit on disk is used by the next delegation,
  while a run of the old definition completes with no change.
- The idle timeout settles a run that stops all activity. A run that waits
  for admission or for its delegates does not time out.

## 15. Items to verify during implementation

- `ToolContext.completionToken` is the correct value for
  `AgentSpawn.parentToolCallId`: it must join to the tool call of the parent
  in the Router transcript. If the two ids are different, ask the Router for
  the tool-call id on `ToolContext`. (M3)
- A tool that an `OperationTool` operation mounts with
  `ToolContext.mount(_:op:as:)` in the `.background` mode gives the pending
  envelope, `runSettled`, and the delivery turn in the same way as a
  background tool that the session registered directly. (M4)
- How a host that drives `streamEvents(to:)` starts the delivery turn:
  `dispatchNextPrompt()` after `runSettled`. An agent run uses the same
  sequence for its own delegates. (M4, M5)
- A `file://` source with `path:` gives the folder unchanged and does not use
  the layout, as §10 says. Confirm it with a real `MarketplaceStore` in the
  integration suite. (M2)

---

### Sources

- Claude Code sub-agents — https://code.claude.com/docs/en/sub-agents
- FoundationModelsRouter — ../FoundationModelsRouter/README.md
- FoundationModelsExtras — ../FoundationModelsExtras/plan.md, README "Remote layers"
- FoundationModelsSkills — ../FoundationModelsSkills/plan.md, docs/marketplaces.md
- What's new in Foundation Models (WWDC26) — https://developer.apple.com/videos/play/wwdc2026/241/
- Build agentic app experiences with Foundation Models (WWDC26) — https://developer.apple.com/videos/play/wwdc2026/242/
