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

- **An agent is an agentic subprocess.** An agent gets a task, makes its own
  context in its own Router session, works in the background with its own
  tools, and gives back one final text. The caller keeps its own context and
  its own turn. This is the Claude Code sub-agent model.
- **An agent is reached through a tool.** The framework has no agent concept.
  This package adds one fused `OperationTool` named `agents`, with four
  operations on one noun: `list agents`, `start agent`, `check agent`,
  `cancel agent`. Because it is a tool as all others are, an agent can have
  it, and thus agents can start agents.
- **Agents learn from skills (§2).** The two packages load the same kind of
  file from the same stack, and the model finds both through a catalog in a
  tool description. This package copies each decision of
  `FoundationModelsSkills` that is not about the context. It does not copy
  the decisions that come from the fact that a skill adds text to the current
  context.
- **Not a code-mode surface.** An agent run is not a function that a script
  calls. The `agents` tool is registered directly on a Router session. It
  does not conform to `OperationDescribing`, so Multitool cannot mount it as
  verbs in a script (§8.5).
- **The minimum semantic layer.** This package owns what is specific to
  agents, and nothing more: the decode of the agent frontmatter, the
  validation, the catalog with identity by `name`, the model match, the tool
  resolution, the runner, and the tool. All file access, all watching, all
  rendering, and all marketplace work are in `FoundationModelsExtras`. This
  is the same boundary that `FoundationModelsSkills` has, and the same guard
  tests enforce it (§14).
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
- **A sub-agent is isolated.** It sees only the task prompt. Only its final
  text goes back to the caller. The calling model has no view into the run. A
  person who wants the detail reads the transcript of the Router session.
- **One run is one task.** A run gets one task prompt, does the task, and
  settles. Its session then closes. There is no follow-up into a settled run.
  A caller that wants more work starts a new run, and puts the necessary
  context into the prompt of that run.
- **Definition, run, and session are different things.** An `AgentDefinition`
  is authored data. An `AgentRun` is one delegated task: the unit of
  scheduling and cancellation. A run drives one Router session and does not
  give that session to other code.
- **The Router decides which models exist.** The `model` value of a
  definition must match a model that the resolved Router profile makes
  available: a slot name or a model reference. This package has no model
  names and no alias table of its own.
- **Parallel by admission, and honest about the GPU.** A FIFO admission gate
  limits how many runs have a turn in operation at one time. The Router
  serializes generation on each resident model. Runs on different slots
  overlap. Runs on the same slot take turns.

## 2. Skills and agents — what transfers

A skill and an agent are both a `.md` file with frontmatter in a layered
stack, with an identity, a description, and a body. The difference is what
the body does:

- The body of a **skill** is text that `use skill` puts into the **current**
  context, at once, in the same turn. The model then does the work itself.
- The body of an **agent** is the system prompt of a **new** context. The
  agent does the work in the background, and only its final text comes back.

Thus each decision of Skills that is about the file, the catalog, or the tool
surface transfers. Each decision that is about text in the current context
does not.

| Skills decision | Agents | Why |
|---|---|---|
| Load through the Extras stack; marketplace layers below local layers; cached catalog; `DotfolderWatcher` and `layerUpdates`; `onReload` | **Same** (§3, §4) | The same files in the same stack. |
| Split and decode the raw frontmatter; render the body later with `StenciledDotfolderStack`; trust by layer | **Same** (§4) | The frontmatter is data; the body is a template. |
| The lenient decode retry for a `description:` value with an unquoted `:` | **Same** (§4) | Claude agent descriptions often hold colons and examples. |
| Name rules, length limits, severities `advisory` / `warning` / `skip`, diagnostics with provenance | **Same** (§4, §9) | The same kind of file. |
| `disable-model-invocation`, `user-invocable` | **Same** (§4, §8.4) | An agent can be for the model only, for the user only, or for the two. |
| A tool description built from the catalog, with a character limit and four forms that degrade | **Same** (§8.1) | The model finds agents the same way it finds skills. |
| The schema pins the ids at `make`; an unknown id gives a corrective answer with the valid ids | **Same** (§8.1) | Small models name ids more reliably from an enum. |
| Plain-text answers for text the model must read, not escaped JSON | **Same** (§8.1) | The Skills evaluation found that a model does not follow an escaped JSON body. |
| `CorrectiveOutcome`: a correction is an answer, not an error | **Same** (§8.1) | The model corrects itself in the same turn. |
| A CLI from `OperationCLIDriver`; a demo with CLI, chat, watch, and marketplace modes; an example library with broken files | **Same** (§8.4, §12) | The same host needs. |
| Guard tests on the source | **Same** (§14) | The same boundary. |
| `use skill` gives the body to the caller | **Not copied.** `start agent` gives the body to a new session. | The body is not for the caller's context. |
| Argument substitution (`$ARGUMENTS`, `$1`, `$name`) and quarantine of the values | **Not copied.** The task prompt is the input, and it is not rendered. | The task goes to the agent as a message, not into a template. |
| Shell injection (`` !`cmd` ``) in the body; `RenderPolicy` | **Not copied.** | A system prompt is static text. An agent runs commands with its own tools. |
| `preload: true` bodies in the host's instructions | **Not copied.** | An agent does not add text to the host's context. The `skills:` key of an agent preloads skills into the agent's own context (§5). |
| Resources and `run script` under the skill folder | **Not copied.** | An agent is one file. It gets tools from the host's `ToolCatalog`. |
| `search skill` | **Not copied.** | Agent catalogs are small. `list agents` gives the full catalog. |
| `OperationDescribing` and `ForkableTool` for Multitool | **Not copied** (§8.5). | An agent is a subprocess, not a script verb. |
| A slash command delivers the raw body as a prompt | **Different** (§8.4). A slash command starts a run. | The user delegates to the agent. The body is not a prompt for the host. |

## 3. Architecture

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
                SlashCommand · SlashCommandProviding
                Operations (OperationTool, @Operation, OperationResolver)
  Marketplace:  MarketplaceLayerProviding · MarketplaceLayer · MarketplaceStore
  Router:       LanguageModelProfile slots · RoutedSession · run plane
                (ToolContext, BackgroundTool) · recording
  Skills:       SkillsRegistry
```

- **Layers 1 and 2 have no model.** They are files and validation only. They
  keep the `model` value as text. The runner matches it against the Router
  profile (§7).
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

## 4. The catalog — locations, format, and load

### 4.1 Layers and identity

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
- **Override of a file is the rule of the stack.** The unit of override is
  the file path. For a path relative to a layer root, the copy in the highest
  layer wins, and each lower copy is hidden. A directory is never replaced:
  it holds the union of the names of all the layers.
- **The `name` frontmatter key is the identity** (the Claude rule). The file
  name and the path do not have to match it.
- **Two winning files with the same `name`.** When the files are in different
  layers, the file in the higher layer wins, with an advisory for the lower
  one. When the files are in the same layer, the last path in a stable sort
  order wins, with a warning. This is the same as the Claude `/doctor`
  duplicate report.
- **Provenance.** Each definition keeps its URL, its layer, and, for a
  marketplace layer, its `MarketplaceProvenance` (the id, the URL, the
  commit).
- **The catalog is cached and rebuilt (the Skills pattern).** The registry
  builds an `AgentCatalog` value and holds it. `catalog()` gives the current
  value and does no file I/O. The registry builds a new catalog and replaces
  the old one atomically when `DotfolderWatcher` reports a change in a local
  layer or in a marketplace layer with `isWatchable == true`, or when the
  marketplace provider reports `layerUpdates`. `onReload` gives a new
  subscription on each access and publishes each new catalog. A host that
  gives `watch: false` and no marketplace provider rebuilds with `reload()`.

### 4.2 Format — a Claude-compatible subset

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

Field tiers: parse all fields, act on tier 1, keep tier 2 as data, report
tier 3.

| Tier | Fields | Behavior |
|---|---|---|
| **1 — enforced** | `name`, `description` (required); `tools`, `disallowedTools`; `model`; `skills`; `maxTurns`; `compactionPrompt` (ours); `disable-model-invocation`, `user-invocable` (the Skills keys) | Full semantics (§5–§8) |
| **2 — data only** | `color`; `background`; all keys that are not known | Available on `AgentListing` for hosts. No behavior. `background: false` cannot be obeyed and gets an advisory, because all runs are background runs. |
| **3 — not supported** | `permissionMode`, `mcpServers`, `hooks`, `memory`, `effort`, `isolation`, `initialPrompt` | Parsed, reported as an advisory, and ignored. A file written for Claude Code loads. |

- `compactionPrompt` is the text of the fold prompt for this agent. When the
  key is absent, the run uses `CompactionPrompt.default`.
- **Visibility has two axes**, with the names and the defaults of Skills:
  - `isModelVisible = description is valid && disable-model-invocation != true`.
    Only a model-visible agent is in the tool description, in the schema, and
    in `list agents`.
  - `isUserInvocable = user-invocable != false`. Only a user-invocable agent
    is a slash command (§8.4).

### 4.3 Load — split, decode, validate

This is the order of `SkillsRegistry`.

1. **Split and decode, on the raw text.** The registry reads each file
   through a `FrontmatterDocumentStack` on the plain `DotfolderStack` of all
   the layers:

   ```swift
   let documents = FrontmatterDocumentStack(
     base: DotfolderStack(layers: marketplaceLayers + stack.layers),
     decode: AgentFrontmatter.decode,
     onDiagnostic: collect)
   let files = documents.tree("agents")   // [path: Located<FrontmatterDocument<AgentFrontmatter>>]
   ```

   The frontmatter is never rendered. `AgentFrontmatter.decode` uses Yams. It
   never throws. When the first decode fails, it makes one retry with the
   Skills rule: it quotes a `description:` line that holds an unquoted `:`,
   and it records a note. This package has its own copy of the rule, because
   the rule in Skills decodes into `SkillFrontmatter`.
2. **Validate.** `AgentDefinition.init` takes one located document and
   applies a table of rules. Each rule has a severity and a message constant:

   | Rule | Severity |
   |---|---|
   | The frontmatter does not decode, also after the retry | skip |
   | The `.md` file has no frontmatter block | skip |
   | `name` absent, or not 1–64 characters of `[a-z0-9-]` with no leading, trailing, or doubled hyphen | skip |
   | `description` absent or empty | warning; the agent is not model-visible |
   | `description` longer than 1024 characters | warning |
   | A tool name or a skill name that is not known (§5) | warning |
   | An unknown name in `disallowedTools` | warning, at the highest priority (§5) |
   | A `model` value with no match (§7, added by the runner) | warning |
   | A field of tier 3, `background: false`, a decode note, a key that is not known | advisory |
   | A lower-layer file with the same `name` | advisory |

   A `skip` gives no definition. A bad file does not stop a good file next to
   it.
3. **Render the body at the start of a run (§8).** The run renders the body
   with `StenciledDotfolderStack.render(_:in:)`, on the winning layer of the
   definition, with the host's `variables` and `partialLocations`. The trust
   comes from the layer: a file of the `defaults` layer renders trusted, and
   a file of each other layer, which includes each marketplace layer, renders
   untrusted. An `{% include %}` finds a partial in the scope that Extras
   gives the layer. There is no argument substitution and no shell
   injection (§2). A render failure fails the run with `bodyRenderFailed`,
   before it makes a session.

## 5. Tools and skills for a sub-agent

- **`ToolCatalog`.** The host registers the available tools by name:
  `name → factory of any FoundationModels.Tool`. Each run gets new instances.
  The `skills` tool from FoundationModelsSkills is one more catalog entry.
- **Resolution (Claude semantics).** When `tools` is absent, the agent gets
  the full catalog. `disallowedTools` is applied first. Then `tools` is
  resolved against the remainder. A tool named in the two lists is removed.
  The MCP patterns `mcp__<server>`, `mcp__<server>__*`, and `mcp__*` are
  prefix matches against catalog names. An unknown tool name gets a warning
  and is skipped. An unknown name in `disallowedTools` is shown first in the
  doctor view, because a dropped deny gives more access than the author
  wanted.
- **Agents can start agents.** The `agents` tool is a tool as all others are.
  The runner supplies it under the catalog name `agents`, so the rules above
  apply to it: a definition with no `tools` key gets it, `tools` can list it,
  and `disallowedTools` can remove it. An `Agent(a, b)` entry (the Claude
  form) gives the `agents` tool with its names limited to `a` and `b`. Each
  run gets its own tool instance from `AgentsTool.make`. The lineage (§8.2)
  records each level, and `AgentEnvironment.maxDepth` stops recursion with no
  end (§9.3).
- **The host makes the `SkillsRegistry` and gives it to this package.**
  `AgentEnvironment.init` has a `skills: SkillsRegistry` parameter. It is
  necessary, and it has no default value. The host uses that one instance for
  the environment and for the `skills` tool in the `ToolCatalog`. A host that
  has no skills gives a registry with no roots.
- **`skills:` preload into the agent's own context.** At the start of a run,
  `SkillsRegistry.call(id:)` gives the rendered body of each listed skill, and
  the run appends it to the instructions of the new session. This is the one
  place where skill text goes into a context, and the context is the agent's.
  A skill that is unknown, or that is not model-visible, gets a warning and is
  skipped.
- **`maxTurns`.** The Router runs the tool loop in one turn. Thus the limit is
  enforced on tool calls: each tool that the run receives has a counting
  decorator. When the count goes above `maxTurns`, the run cancels the turn
  and fails with `hitMaxTurns`. The failure contains the partial text.
  *Divergence:* Claude counts agentic turns and stops silently. This package
  counts tool calls, which is a tighter limit, and reports a failure.

## 6. Marketplaces of agents

- **The registry takes any `MarketplaceLayerProviding`.** It reads
  `tree("agents")` in each marketplace layer, as it reads a local layer.
- **A `file://` source with `path:` holds agents.** `MarketplaceStore` uses
  `<folder>/<path>` as the layer root, unchanged, with no resolver and no
  snapshot. A folder that holds `agents/**/*.md` thus gives agents. This is
  the supported way to share agents through a marketplace.
- **A git source holds no agents.** For a git source, the shipped resolver and
  snapshot writer copy only the entry folders of the layout, the plugin
  `skills` folders, and the partials. A layer from a git source thus has no
  `agents/` folder. This is not an error: the registry reads an empty tree.
- **One store can serve the two registries.** A `file://` source with `path:`
  does not use the layout, so the host can give the same store to
  `SkillsRegistry` and to `AgentRegistry`.
- **Marketplace diagnostics stay with the marketplace.** A fetch failure, a
  blocked source, or a snapshot limit is a `MarketplaceDiagnostic` or a
  `MarketplaceEvent` of the host's store. This package does not copy them.

## 7. Model selection — frontmatter to a Router model

The `model:` value must match a model that the Router makes available. A
resolved `LanguageModelProfile` makes two language models available:
`profile.standard` and `profile.flash`. Each one has a `chosen: ModelRef`.
This package has no model names and no alias table of its own.

| `model:` value | Result |
|---|---|
| absent / `inherit` | the slot of the caller (see below) |
| a slot name: `standard` or `flash` (the `ModelSlot` raw values) | that slot |
| a model reference equal to the `chosen.stringValue` of a slot, or to its repository part (the text before `@`) | that slot |
| all other values | a warning, then `inherit` |

- **The slot of the caller.** When an agent run started this run, the runner
  knows the slot of that run from its index, and `inherit` gives that slot.
  When a host session or host code started this run, `inherit` gives
  `AgentEnvironment.defaultSlot` (default `.standard`).
- When the two slots have the same chosen model, a model reference matches
  `standard`.
- `embedding` is a Router slot but not a language model. It gets the warning.
- The Claude aliases (`opus`, `sonnet`, `haiku`, `fable`) are not Router
  models. A file written for Claude Code loads, gets the warning, and runs on
  the `inherit` slot.
- **The match needs the profile, so the runner does it.** Layer 1 checks only
  that `model` is a non-empty string. `runner.catalog()` takes the current
  registry catalog and applies the match. A run matches again when it starts.

*Divergence:* Claude also obeys a `CLAUDE_CODE_SUBAGENT_MODEL` environment
variable and a `model` parameter on its Agent tool. This package has neither.

## 8. Execution — one run drives one Router session

An `AgentRun` does these steps:

1. **Resolve** the definition: `registry.catalog().definition(named:)`. The
   run keeps that definition for its full life. A later catalog does not
   change a run.
2. **Render the body** (§4.3, step 3). A failure fails the run.
3. **Assemble instructions**, in this order: the `AgentsMd.documents(from:)`
   texts for the run's working directory (outermost first), the rendered
   body, the rendered `skills:` bodies.
4. **Resolve tools** (§5) and put the counting decorator on each one.
5. **Match the model** (§7), then **make the session** on the slot handle:

   ```swift
   let model = slot == .flash ? profile.flash : profile.standard
   let session = model.makeSession(
     instructions: instructions,
     workingDirectory: workingDirectory,
     tools: tools,
     budget: environment.budget(model.contextTokens),   // TokenBudget
     compactionPrompt: definition.compactionPrompt ?? .default,
     agentSpawn: spawn                                   // §8.2; nil for a host-driven run
   )
   ```

6. **Wait for admission** (§9.3), then drive one turn with
   `session.streamEvents(to: prompt)`. The run reads the events of the turn
   for two functions: the final text, and the progress posts (§9.2).
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

### 8.1 The object model

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
  id of a removed record gives a corrective answer.

### 8.2 Lineage

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
- A host-driven run and a slash-command run have no caller. Their
  `agentSpawn` is `nil`.
- The agent `name` is in the transcript of the caller: it is an argument of
  the `start agent` tool call that `parentToolCallId` points to.
- The caller can be a host session or the session of an agent run. The rule
  is the same, so the `agentSpawn` values make a chain through all levels.

The Router record is thus sufficient to show which session started which
agent. This package adds no lineage data of its own.

## 9. Delegation — the `agents` tool and the scheduler

### 9.1 The tool, the description, and the answers

`AgentsTool.make(context:catalogCharacterLimit:)` builds the tool. It is a
wrapper around an `OperationTool<AgentsToolContext>`, the same shape as
`SkillsCatalogTool`. `make` reads the catalog one time. A host makes a new
tool for each new calling session. The runner makes a new tool for each run
that gets the `agents` tool.

**The description is built from the catalog, as in Skills.**

- It starts with fixed sentences that are never cut. They say what an agent
  is and how to delegate:

  > Agents are helpers that work in the background. Each agent starts with
  > an empty context and sees only the prompt that you give it, so put all
  > that the agent needs in the prompt. To give a task to an agent, call this
  > tool with {"op": "start agent", "name": "<name>", "prompt": "<the full
  > task>"}. After you start agents, end your turn. You get the result of
  > each agent when it finishes.

- The list of model-visible agents follows, under
  `catalogCharacterLimit` (default `SkillsTool.defaultCatalogCharacterLimit`,
  8000). The builder uses the first form that fits: full `- name:
  description` lines; each description cut to 200 characters at a word
  break; names only; as many names as fit, then "`N` more agents are not
  listed. See them with `list agents`."
- An empty catalog gives the first sentence and "No agents are installed
  now."

**The schema pins the names at `make`, as in Skills.** The `name` parameter is
`anyOf` the model-visible names of the catalog at that time, limited by the
`Agent(a, b)` form when the context has one. With no visible agent, it is a
plain string.

**A reload and a tool that was made before it (the Skills behavior):**

- A changed agent: the next `start agent` uses the new definition, because
  the operation reads `runner.catalog()` when the call occurs.
- A removed agent: `start agent` gives a corrective answer that contains the
  current names.
- An added agent: `list agents` shows it, but the schema of this tool does not
  contain its name. The next tool, for the next session, has it.

**Answers are plain text for what the model reads, as in Skills.** The
operations give `CorrectiveOutcome` values: `.success` or `.corrective(String)`.
A correction is an answer that the model can act on in the same turn, never
a thrown error.

| op | parameters | success answer | corrective answers |
|---|---|---|---|
| `list agents` | `filter?` | Plain text: one `- name: description` line for each model-visible agent that matches, from the current catalog, then the delegation sentence. | none. "No agents are available." is a success. |
| `start agent` | `name`, `prompt` | The Router `PendingRunEnvelope`: `pending`, `completionToken`, `next`. | An unknown or removed name: "The agent `x` is not available now. Available agents: a, b." A name that `Agent(a, b)` does not permit. A depth above `maxDepth`. A blank prompt. |
| `check agent` | `id?`, `seconds?` | Plain text. Finished: "Agent `name` (`id`) finished." and the full final text. Failed or cancelled: the state and the reason. Running or queued: "Agent `name` (`id`) is running: `lastEvent`. End your turn; you get the result when it finishes." With `id` absent, one short block for each run of this caller. | An unknown or removed id, or an id of a different caller: "No run has the id `x`." and the ids of this caller's runs. |
| `cancel agent` | `id` | Plain text: the `CancelOutcome` of the run. | The same as `check agent`. |

`seconds` (default 0) is how long `check agent` waits for the run to settle.
The resolver adds these verb aliases: `stop` → `cancel`, `run` → `start`,
`status` → `check`, `show` → `list`.

### 9.2 Background runs on the Router run plane

`start agent` does not do the work in its own call. It mounts an internal
tool, `AgentRunTool`, with `ToolContext.current.mount(_:op:as:)` in the
`.background` mode, and calls it.

- `AgentRunTool` conforms to `BackgroundTool`. Its `runKind` is `.swiftTask`.
  Its `collectInstruction(forCompletionToken:)` tells the model to end its
  turn. Its `canceler(forCompletionToken:)` calls
  `session.cancelCurrentTurn()` on the run's session and reports
  `.cancelled`.
- The Router returns the `PendingRunEnvelope` at once. The body of the run
  continues: admission, the turn, the delegates of the run, the result.
- **One run, one token.** The completion token of the background run is the
  `id` that the model uses. The runner maps the token to the run.
- **Progress.** The body posts `ToolContext.progress(_:)` for each tool call
  and each recorded entry of the sub-agent, and at a fixed interval while it
  waits for admission or for its delegates. The idle timeout of the mount
  (`AgentEnvironment.idleTimeout`) thus means "no activity", not "total
  time".
- **Settlement.** The terminal event carries the result as its `detail`. The
  Router keeps only the last `ToolContext.terminalDetailTailLimit` (4096)
  characters of a detail. Thus:
  - A final text that fits is the detail, unchanged.
  - A longer final text gives a detail with its first part, then "The full
    result has `N` characters. Call `check agent` with the id `x` to read
    it." The model thus knows that the text was cut, and where to get the
    rest.
- **Notification is the Router's.** When the run settles, the host receives
  `SessionEvent.runSettled`. The calling model receives the result in a
  delivery turn: `respond(to:)` drains the run plane after its own turn, and
  `dispatchNextPrompt()` runs the delivery turn for a host that drives
  `streamEvents(to:)`. An agent run is such a host for its own session (§8,
  step 7).
- **`check agent`** calls `ToolContext.wait(completionToken:seconds:)`.
  **`cancel agent`** calls `ToolContext.cancel(completionToken:)`.
- **Close.** `close()` on the calling session sweeps its mailbox, and the
  sweep runs the canceler of each open run. The cancel of a run thus goes
  down to the runs that it started.

**Outside a Router session** `ToolContext.current` is `nil`. This is the case
for a native `LanguageModelSession`. The operations then use the runner
directly. `start agent` returns an envelope whose token is the run id. There
is no delivery turn, and the model uses `check agent`.

### 9.3 `AgentRunner` — admission and the index

`AgentRunner` is an actor. It owns each `AgentRun`. It is not a session
system, a tool loop, a recorder, a notifier, or a display model.

- **Admission.** At most `maxConcurrentAgents` runs have a turn in operation.
  More runs wait in a FIFO queue. The Router has no admission gate for
  sessions. The Router's generation gate, one for each resident model,
  serializes the generation calls below this gate.
- **A run holds admission only during a turn.** A run that waits for its
  delegates holds no admission (§8, step 7). Thus a parent cannot block its
  children, and a full gate of parents cannot stop all work.
- **Depth.** A run that a host session, host code, or a slash command started
  has depth 1. A run that an agent run started has the depth of that run
  plus 1. `AgentEnvironment.maxDepth` (default 3) is the limit.
- **The index.** `runs`, `run(id:)`, the token → run map, and, for each run,
  its caller (`ToolContext.sessionID`, or `nil`), its slot, and its depth.
  The index holds the runs in operation and the records of the settled runs
  (§8.1). It is for program control: to find, check, and cancel runs.
- **`runner.catalog()`**: the current registry catalog with the model match
  (§7).
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

### 9.4 Slash commands and the CLI

**Slash commands start a run.** `AgentRunner` conforms to the Extras
`SlashCommandProviding`, as `SkillsRegistry` does:

- `commands(workingDirectory:)` gives one `SlashCommand` for each
  user-invocable agent of the current catalog: `name` is the agent name,
  `description` is the agent description, and `argumentHint` is `<task>`.
- The body is `.action`. The action starts a host-driven run with the
  arguments of the invocation as the task prompt and the working directory of
  the invocation. It streams one line for each progress post, and then the
  final text.
- `commandUpdates` gives a new command list for each catalog of `onReload`.

Thus `/code-reviewer check the diff` is the user's way to delegate, as the
`@` mention is in Claude Code. The Skills slash command gives the raw body as
a prompt for the host's context. An agent command does not, because the body
is not for the host's context (§2).

**The CLI.** `AgentsCLI.makeDriver(runner:)` gives an `OperationCLIDriver`
over the same four operations, with the executable name `agents`: `agents
agent list`, `agents agent start --name … --prompt …`, and so on. A command
line has no delivery turn, and the process ends after the command. Thus the
CLI `start` waits for the run to settle and prints the final text, and
`check` and `cancel` are for a host process that stays alive.

### 9.5 Not a code-mode surface

Multitool's code mode mounts a tool that conforms to `OperationDescribing` as
one function for each operation, and a script calls those functions. Skills
conforms, because `use skill` is a synchronous call that gives text.

`AgentsTool` does not conform to `OperationDescribing` or `ForkableTool`:

- An agent run is a subprocess with its own context, its own turn, and a
  background life. A script call that returns at once with a pending
  envelope, or that holds the script for the full run, is the wrong model.
- The lineage, the delivery turn, and the cancel sweep need a Router session
  as the caller. A script is not one.

A host that wants agents registers the `agents` tool directly on its Router
session, next to Multitool if it uses Multitool.

## 10. Recording and diagnostics

- **Recording is the Router's.** Each run has `transcript.jsonl` and
  `session.json` in its session directory. `Router(recordingsDir:recorder:
  recordingLevel:redact:)` controls the location, the level, and the
  redaction. This package writes no recording files.
- **Visibility is the Router's.** A host that shows agent work shows Router
  sessions and transcripts. The lineage in §8.2 connects the session of a
  sub-agent to the tool call that started it. This package has no observable
  display types, no transcript browser, no transcript index, and no tree
  builder.
- **Diagnostics are data, and they belong to one catalog.**
  `AgentCatalog.diagnostics` is `[AgentDiagnostic]` for the build of that
  catalog. The shape is the shape of `SkillDiagnostic`: a severity
  (`advisory`, `warning`, `skip`), the agent name when it is known, a
  provenance (the layer index, the layer root, the file URL, and the
  `MarketplaceProvenance` for a marketplace layer), and a message.
  `runner.catalog()` adds the `model` warnings (§7).
- **The reload report.** `AgentReloadReport` gives lines for a watch view:
  the number of agents, the number of model-visible agents, the slash-command
  names, and the diagnostic counts. It is the same idea as the Skills
  `ReloadReport`.

## 11. Dependencies

| Package | Products | Used for |
|---|---|---|
| `FoundationModelsRouter` | `FoundationModelsRouter` | `LanguageModelProfile`, `ModelSlot`, `ModelRef`, `RoutedSession`, `SessionEvent`, `ToolContext`, `BackgroundTool`, `ToolMount`, `TokenBudget`, `CompactionPrompt`, `SessionSidecar.AgentSpawn` |
| `FoundationModelsExtras` | `FoundationModelsExtras`, `Marketplace`, `Operations`, `OperationsCLI` | `DotfolderStack`, `FrontmatterDocumentStack`, `FrontmatterDocument`, `Located`, `DotfolderWatcher`, `StenciledDotfolderStack`, `QuarantinedText`, `AgentsMd`, `SlashCommand`, `SlashCommandProviding`; `MarketplaceLayerProviding`, `MarketplaceLayer`, `MarketplaceProvenance`; `OperationTool`, `@Operation`, `OperationResolver`; `OperationCLIDriver` |
| `FoundationModelsSkills` | `FoundationModelsSkills` | `SkillsRegistry` for the `skills:` preload; `SkillsTool.defaultCatalogCharacterLimit`; `CorrectiveOutcome` |
| Yams, ULID.swift | | `AgentFrontmatter.decode`; ids |

All the sibling APIs in this plan are shipped. There is no prerequisite work
in a sibling repository.

Packaging: one SwiftPM library target, `FoundationModelsAgents`, and one
executable target, `agents-demo`, in the same package. Sibling packages are
remote dependencies on the `main` branch, not `path:` dependencies. Swift
tools 6.2. `.macOS("27.0")`. There is no fallback for earlier systems.

**Naming.** `FoundationModelsSkills` brings in `FoundationModelsRanker` and
`FoundationModelsMetadataRegistry`, which export a protocol named
`AgentSession` for their selection step. It is not related to sub-agents. The
public nouns of this package are `AgentDefinition`, `AgentRegistry`,
`AgentRun`, `AgentRunner`, and `AgentsTool`. This package does not use the
name `AgentSession`.

## 12. Public API sketch

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

// Host-driven runs.
let report = try await runner.start("code-reviewer", prompt: "Review:\n\(diff)").result()

// The user's `/` menu.
let commands = await runner.commands(workingDirectory: projectURL)   // [SlashCommand]

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

`AgentRegistry` has the initializer shapes of `SkillsRegistry`:
`init(stack:variables:watch:)`, `init(layers:variables:watch:)`, and
`init(marketplaces:stack:variables:watch:)`.

Core types: `AgentFrontmatter`, `AgentDefinition`, `AgentListing`,
`AgentRegistry`, `AgentCatalog`, `AgentDiagnostic`, `AgentReloadReport`,
`AgentEnvironment`, `ToolCatalog`, `AgentsTool`, `AgentsToolContext`,
`AgentRunner`, `AgentRun` (`id`, `agent`, `caller`, `depth`, `state`,
`recordingDirectory`, `result()`, `cancel()`), `AgentRunState` (`queued`,
`running`, `finished(String)`, `failed(AgentRunFailure)`, `cancelled`),
`AgentRunFailure` (`bodyRenderFailed`, `hitMaxTurns`, …), `AgentsCLI`.

## 13. Examples — `./Examples`

The layout of the Skills examples:

```
Examples/
  agent-library/            fixture layers; the tests use them too
    defaults/agents/          code-reviewer.md (flash; tools: Read, Grep)
                              test-writer.md (standard)
                              lead.md (tools: Agent(code-reviewer, test-writer))
    defaults/_partials/       house-rules.md
    user/agents/              a user copy of code-reviewer.md
    project/.agents/agents/   project agents; one with user-invocable: false
    marketplace/agents/       security-reviewer.md; used as a file:// source
    broken/agents/            bad-colon-description.md, missing-description.md,
                              bad-name.md, no-frontmatter.md,
                              unknown-model.md, unknown-disallowed-tool.md
  agents-demo/              one executable with modes:
                              (default)       the CLI over the four operations
                              --chat          a Router session with the agents
                                              tool: start, delivery turn, check;
                                              the lead agent starts two agents
                              --fan-out       host-driven runs on the two slots;
                                              prints which runs overlap
                              --watch         prints an AgentReloadReport on
                                              each onReload
                              --marketplace   adds the marketplace folder as a
                                              file:// source
```

`--chat` needs a resolved Router profile. The other modes run with no model.

## 14. Milestones

- **M1 — `AgentDefinition`.** `AgentFrontmatter.decode` with Yams and the
  lenient retry. The rule table of §4.3 with severities and message
  constants, the visibility axes, tool-list parsing. Hermetic tests with
  `Located` fixtures and `agent-library/broken`.
- **M2 — `AgentRegistry`.** The layer plan, the read through
  `FrontmatterDocumentStack` and `tree("agents")`, identity by `name`, the
  same-name rules, provenance, `AgentCatalog`, `AgentDiagnostic`, the cache
  with atomic replacement, the rebuild from `DotfolderWatcher` and
  `layerUpdates`, `onReload`, `reload()`, `AgentReloadReport`. The guard
  tests. Tests with `MarketplaceFixtures`. *Needs M1.*
- **M3 — `AgentRun`.** One run from start to end on a Router session: the body
  render on the winning layer; instructions from `AgentsMd`, body and skills;
  tool resolution; the model match; the budget and the fold prompt;
  `agentSpawn`; the final text; the close of the session. `run.cancel`.
  *Needs M1.*
- **M4 — `AgentsTool`.** The wrapper tool, the description builder with the
  four forms, the pinned schema, the plain-text answers and the corrective
  answers, `list agents`, `start agent`, `check agent` on the Router run
  plane: the pending envelope, lineage, progress posts, settlement with the
  long-result rule, the delivery turn. The path outside a Router session.
  `agents-demo --chat`. *Needs M2 and M3.*
- **M5 — Scheduler and nested runs.** The admission gate, `cancel agent`,
  `check agent` with no id, the records of settled runs and
  `maxRetainedRuns`, runner stop. Nested runs: the `agents` tool in the tool
  set of a run, the wait for delegates with no admission held, `inherit` from
  a calling run, `maxDepth`, cancel that goes down to the started runs.
  `agents-demo --fan-out`. *Needs M4.*
- **M6 — Semantics and user surfaces.** `skills:` preload, the
  `disallowedTools` order and the MCP patterns, the `Agent(a, b)` limit, the
  `maxTurns` decorator, the idle timeout. `SlashCommandProviding`,
  `AgentsCLI`, `agents-demo` default, `--watch`, and `--marketplace`.
  *Needs M4.*
- **M7 — Finish.** DocC, the README with a compiled example, a document on
  marketplaces of agents (§6), a document on skills and agents (§2). *Needs
  M5 and M6.*

## 15. Testing

**Guard tests, copied from Skills.** They scan each line of
`Sources/FoundationModelsAgents/`, comments included:

- **`LoadingBoundaryTests`**: the 16 names of the Skills list that apply here
  (`FileManager`, `FileHandle`, `String(contentsOf`, `Data(contentsOf`,
  `resourceValues`, `contentsOfDirectory`, `DispatchSource`, `O_EVTONLY`,
  `resolvingSymlinksInPath`, `FrontmatterDocument.split`, `TemplateEngine`,
  `TemplateContext`, `TemplateValue`, `WellKnownValues`, `import Stencil`,
  `import libgit2`). Each forbidden name has the reason: the Extras type that
  owns that work. An exemption that is not used fails the test.
- **`NoStandardOutWriteTests`**: no `print(`, `debugPrint(`, `dump(` in
  `Sources/` and in `Examples/agents-demo/`, except through one output
  helper.
- **`NoDotfolderStackExtensionTests`**: no `extension DotfolderStack`.
- **`NoCodeModeConformanceTests`**: no `OperationDescribing` and no
  `ForkableTool` conformance in `Sources/` (§9.5).
- **`ReadmeExampleTests`**: the README example compiles.

**Hermetic unit tests**, for each milestone: the rule table, identity and
precedence, tool-list resolution, the model match, the `maxTurns` decorator,
admission and cancellation. They use `agent-library`, `MarketplaceFixtures`,
and the Router's test-support sessions. They use no real model.

**The layer rules are a tested case.** With `agent-library` and a fixture
marketplace provider:
- A project copy of a path replaces the lower copies of that path.
- The same `name` in two layers gives the higher layer and an advisory. The
  same `name` two times in one layer gives the last path and a warning.
- A definition from a marketplace layer has its provenance in the listing
  and in its diagnostics.
- A marketplace layer with no `agents/` folder gives no agents and no
  diagnostic.
- A `{{ }}` in the frontmatter stays as text. A `description:` with an
  unquoted `:` decodes on the retry, with a note.
- The body of a `defaults` file renders trusted, and the body of a user,
  project, or marketplace file renders untrusted. A local body cannot include
  a partial that only a marketplace has, and the run fails with
  `bodyRenderFailed`.
- Each file of `broken/` gives its diagnostic, and the good files next to it
  load.

**The tool surface is a tested case.**
- The description takes each of the four forms at the correct catalog size,
  and the fixed sentences are never cut.
- An agent with `disable-model-invocation: true` is not in the description,
  the schema, or `list agents`, and is a slash command.
- An agent with `user-invocable: false` is not a slash command.
- Each corrective answer of §9.1 has its text and its valid names or ids.
- A result longer than 4096 characters gives the cut detail with the
  `check agent` sentence, and `check agent` gives the full text.

**Reload is a tested case.** Add, change, and remove a definition on disk.
The watcher rebuilds the catalog, and `onReload` publishes it. A
`layerUpdates` event from the fixture provider rebuilds the catalog. A burst
of edits gives one consistent final catalog. A run in operation is not
changed. For a tool that was made before the reload: `start agent` of a
changed name uses the new definition; `start agent` of a removed name gives
the corrective answer; an added name is in `list agents` and in the next
tool, and not in the schema of this tool. `commandUpdates` gives the new
commands.

**The model match, the life of a run, and nested runs are tested cases.**
- A slot name and a chosen model reference give that slot. A Claude alias,
  `embedding`, and an unknown reference give a warning and the `inherit`
  slot. `inherit` from a calling run gives the slot of that run.
- A settled run holds no session. When the number of settled records goes
  above `maxRetainedRuns`, the oldest record is removed.
- With `maxConcurrentAgents` equal to 1, a parent run does not block its
  child. `start agent` above `maxDepth` starts no run. The cancel of a parent
  cancels its open children. A caller cannot address a run of a different
  caller.

**A real-model integration suite** is in a nested `IntegrationTests/`
package, the Router pattern: Swift Testing, `.serialized`, enabled by an
environment variable, small `mlx-community` models. It needs a separate
package because it downloads models. It proves these cases:

- A definition file, and a definition from a `file://` marketplace folder
  through a real `MarketplaceStore`, each become a live sub-agent.
- A definition with the model reference of the flash slot runs on the flash
  slot.
- Background delegation goes full circle: the root model calls `start agent`,
  the sub-agent uses a tool, the run settles, the host receives `runSettled`,
  the delivery turn gives the result to the root model, and `check agent`
  gives the full text.
- An agent starts a second agent, and the `agentSpawn` values link the three
  sessions. `parentToolCallId` joins to the `start agent` tool call in the
  transcript of the caller.
- A slash command runs an agent and streams its progress and its result.
- Two runs on different slots make progress independently. `cancel agent`
  stops a run.
- A live edit, end to end: an edit on disk is used by the next delegation,
  while a run of the old definition completes with no change.
- The idle timeout settles a run that stops all activity. A run that waits
  for admission or for its delegates does not time out.

## 16. Items to verify during implementation

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
- The plain-text answers use the Skills method: the operation gives text,
  and the wrapper decodes the JSON string that `OperationTool` makes. (M4)
- A `file://` source with `path:` gives the folder unchanged and does not use
  the layout. Confirm it with a real `MarketplaceStore`. (M2)

---

### Sources

- Claude Code sub-agents — https://code.claude.com/docs/en/sub-agents
- FoundationModelsRouter — ../FoundationModelsRouter/README.md
- FoundationModelsExtras — ../FoundationModelsExtras/plan.md, README "Remote layers"
- FoundationModelsSkills — ../FoundationModelsSkills/README.md, docs/operations.md, docs/marketplaces.md, CHANGELOG.md
- FoundationModelsMultitool — ../FoundationModelsMultitool/README.md (code mode)
- What's new in Foundation Models (WWDC26) — https://developer.apple.com/videos/play/wwdc2026/241/
- Build agentic app experiences with Foundation Models (WWDC26) — https://developer.apple.com/videos/play/wwdc2026/242/
