# Plan: FoundationModelsAgents — Claude-style sub-agents for Foundation Models

A Swift package that loads [Claude Code sub-agent](https://code.claude.com/docs/en/sub-agents)
definition files from stacked directories and exposes them to Apple's
[Foundation Models framework](https://developer.apple.com/videos/play/wwdc2026/241/) through
**one tool** — `AgentsTool` — with a scheduler that runs **many agents in parallel** for
multi-tasking. Models come from [`../FoundationModelsRouter`](../FoundationModelsRouter/plan.md);
the generic stacked-folder machinery comes from
[`../FoundationModelsSkills`](../FoundationModelsSkills/plan.md).
**Primary target: macOS, on-device.**

---

## 1. Guiding principles

- **An agent is just a tool — no special case.** In an FM session, sub-agents are reached
  through one `FoundationModels.Tool` — `AgentsTool` (**list / run / start / check / send /
  cancel**).
  The framework has no agents concept; we add a *tool*, not a new primitive. This mirrors
  Claude Code, where delegation happens through the `Agent` (né `Task`) tool. But it is a
  **special tool result**: every action returns a typed `AgentEvent` that lands in the
  calling session's transcript as a structured segment (§8.2), so agent starts/stops are
  first-class entries in the caller's record, not prose.
- **A sub-agent is a fresh, isolated session.** Each run gets its own
  `LanguageModelSession`: its own context window, its own system prompt (the definition body),
  its own tool set, its own working directory. It sees only the task prompt the caller
  composed — never the parent's transcript. Only its **final text** returns to the caller.
- **Definition ≠ run ≠ session.** An `AgentDefinition` is authored data; an `AgentRun` is
  one delegated task — the unit of identity, scheduling, cancellation, recording, and UI —
  and it **owns** its session, which is never vended (§7.1). One definition, many concurrent
  runs; follow-ups go through the run, whose session (and context) lives as long as the run
  handle.
- **Descriptions are the delegation contract.** Agent catalogs are small (unlike skills), so
  each agent's `name` + `description` are baked directly into the `AgentsTool` surface — the
  root model reads them to decide when and where to delegate. No separate search agent.
- **Models are routed, never named.** A definition says *how much* model it wants
  (`standard` / `flash` / `inherit`), not *which* HF repo — the Router already solved
  machine-fit. Claude aliases (`opus`, `sonnet`, `haiku`, `fable`) map onto slots.
- **Parallel by admission, honest about the GPU.** An `AgentRunner` actor schedules runs
  under a fair FIFO admission gate (`maxConcurrentAgents`). Runs genuinely interleave and
  runs on *different* slots (standard vs flash) genuinely overlap — but generation on one
  resident model is serialized by the Router's per-model gate, and we say so rather than
  pretend otherwise.
- **Reuse the stack, don't refork it.** `FrontmatterDocument` + `FolderStack` (Skills
  layers 1–2) parse and stack the definition files; `SkillsRegistry` powers the `skills:`
  preload. The Skills plan already anticipated this ("the same stack also serves agents");
  this package **is** that consumer (see §10 for the cross-repo consequences).
- **macOS-first, on-device.** iOS is a graceful "unavailable" stub.

## 2. Layered architecture

```
┌─ Layer 4  FM adapter (agents) ─────────────────────────────────────────────┐
│   AgentsTool — one core FoundationModels.Tool: list / run / start /        │
│                check / send / cancel                                       │
│   AgentRunner — actor: parallel runs, fair admission, cancellation         │
│   AgentRun — one delegated task: owns its session; identity, state, result │
│   AgentActivity — @Observable per-profile dashboard (runs + slot lanes)    │
├─ Layer 3  AgentRegistry  (domain validation + semantics) ──────────────────┤
│   Claude sub-agent frontmatter validation, name identity + precedence,     │
│   tools/disallowedTools resolution, model mapping, skills preload,         │
│   listing → injectable metadata — built ON the Skills FolderStack          │
├─ Layer 2  FolderStack  (from FoundationModelsSkills) ──────────────────────┤
│   ordered roots; recursive discovery; FULL-REPLACE override by name;       │
│   list(); entry(name:); file-watch add/remove/reload up the stack          │
├─ Layer 1  FrontmatterDocument  (from FoundationModelsSkills) ──────────────┤
│   parse one .md → (YAML frontmatter, markdown body); serialize back        │
└────────────────────────────────────────────────────────────────────────────┘
     Execution substrate: FoundationModelsRouter — LanguageModelProfile slots
     (.standard / .flash), resident models, per-model serial gate, recording
```

- Layers 1–2 are **imported from `FoundationModelsSkills`**, not reimplemented. One
  generalization is required there: agents are **flat `*.md` files scanned recursively**
  (Claude layout), not `name/SKILL.md` directories — the `EntryKind` must support a
  file-shaped entry (§10).
- **`AgentRegistry`** (Layer 3, the source of truth) — wraps a `FolderStack<Agent>`; adds
  Claude-compatible validation (§4), identity + precedence (§3), tool-list resolution (§5),
  model mapping (§6), and skills preload (§5). Reloadable; publishes refreshed metadata.
- **FM adapter** (Layer 4) — `AgentsTool`, `AgentRunner`, `AgentRun`, all reading the
  registry and executing over Router-vended models.

## 3. Identity, locations & precedence

- **`name` frontmatter = canonical id** (Claude rule: identity comes from `name`, the
  filename doesn't have to match). Validated: lowercase letters and hyphens. This differs
  deliberately from Skills' directory-name identity — agents are single files and we follow
  the Claude spec for them.
- **Roots are caller-supplied, ordered low → high precedence**, e.g.
  `[~/.claude/agents, <project>/.claude/agents]` — user-wide first, project overrides.
  Override is **full replace by `name`** up the stack (same rule as Skills).
- Each root is scanned **recursively**; subdirectories organize, they don't namespace
  (matching Claude's project/user scan behavior).
- **Duplicate `name` within one root** ⇒ one wins deterministically (last in stable sort
  order) and a **diagnostic** is emitted — mirroring Claude's `/doctor` duplicate report.
- The **file watcher** applies add/remove/edit across every root; the registry rebuilds and
  publishes refreshed metadata (Claude requires a restart — we do better because the
  FolderStack already watches).

## 4. Definition format — Claude-compatible subset

One `.md` file: YAML frontmatter + body. **The body is the sub-agent's system prompt**,
verbatim — it is *not* rendered through the skills argument/shell/Stencil pipeline (a system
prompt is authored static text; the dynamic part of a run is the task prompt). Example:

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

Field support tiers — parse everything, act on tier 1, carry tier 2 as data, diagnose tier 3:

| Tier | Fields | Behavior |
|---|---|---|
| **1 — enforced** | `name`, `description` (required); `tools`, `disallowedTools`; `model`; `skills`; `maxTurns`; `background` | Full semantics (§5–§7) |
| **2 — data only** | `color`, plus all unrecognized `metadata`-style keys | Exposed on `AgentListing` for hosts/UI; no behavior |
| **3 — unsupported** | `permissionMode`, `mcpServers`, `hooks`, `memory`, `effort`, `isolation`, `initialPrompt` | Parsed, surfaced as a **diagnostic** ("field X is not supported by FoundationModelsAgents"), otherwise ignored — a Claude-authored file still loads |

`description` is the delegation contract (injected into the `AgentsTool` surface) — the
"use proactively" convention works here exactly as in Claude Code, because the root model
reads the same words.

## 5. Tools & skills for a sub-agent

- **`ToolCatalog`** — the host registers the universe of available tools by name:
  `name → any FoundationModels.Tool` (factories, so each run gets fresh instances where a
  tool is stateful). The `SkillsTool` from FoundationModelsSkills is just another catalog
  entry.
- **Resolution (Claude semantics):** omit `tools` ⇒ inherit the **whole catalog**;
  `disallowedTools` is applied first (removed from inherited or specified list), then
  `tools` is resolved against the remainder; a tool named in both is removed. Unknown tool
  names ⇒ diagnostic, skipped.
- **No nested agents in v1.** The `AgentsTool` is never placed in a sub-agent's tool set,
  and a definition listing it draws a diagnostic. (Claude allows depth 5; we start at 1 —
  a depth-limited nesting option is a clean later extension.)
- **`skills:` preload** — when the environment carries a `SkillsRegistry`, each listed
  skill's **rendered body** is appended to the sub-agent's instructions at run start (full
  content, not just the description — Claude's `skills` semantics). Missing or
  `disable-model-invocation` skills are skipped with a diagnostic. Without a registry, the
  field draws a diagnostic.
- **`maxTurns`** — FM's session runs its tool loop inside one `respond` call, so we enforce
  the bound structurally: every tool handed to the run is wrapped in a **counting decorator**;
  when the count crosses `maxTurns` the run is cancelled and reports
  `.failed(hitMaxTurns)`. Best-effort but real — no tool call escapes the wrapper.

## 6. Model mapping — frontmatter → Router slot

A resolved `LanguageModelProfile` supplies the models; the definition picks a slot:

| `model:` value | Resolves to |
|---|---|
| *(omitted)* / `inherit` | the environment's **default slot** (the slot backing the root session; configured on `AgentEnvironment`) |
| `standard` *(ours, canonical)* | `profile.standard` |
| `flash` *(ours, canonical)* | `profile.flash` |
| `opus`, `sonnet`, `fable` *(Claude aliases)* | `profile.standard` |
| `haiku` *(Claude alias)* | `profile.flash` |
| full model id (e.g. `claude-opus-4-8`, an HF repo) | **diagnostic; falls back to `inherit`** — picking repos is the Router's job, not a definition's |

The alias table lives in a `ModelMapping` value (default above, host-overridable), so a
Claude-authored agent file runs unmodified while our canonical vocabulary stays
slot-shaped.

## 7. Execution — one run, one session

`AgentRun` is one delegated task:

1. **Resolve** the agent from the live registry (stale name ⇒ error carrying the current
   listing, same backstop pattern as `SkillsTool.call`).
2. **Assemble** instructions = definition body + rendered `skills:` preloads; tools = §5
   resolution, each wrapped in the counting decorator; model = §6 slot.
3. **Run** a fresh **native `LanguageModelSession`** over the slot's resident model (via the
   Router's FoundationModels interop — `MLXLanguageModel`; §10), submitting the caller's
   task prompt. Apple's framework drives the tool loop, `@Generable` availability, etc.
4. **Return** the session's final text as the run's result. Tool traffic, intermediate
   turns, and context stay inside the run.

Why native `LanguageModelSession` and not the Router's `RoutedSession`: sub-agents are
useful *because they can use tools*, `RoutedSession` has no tool surface, and the Skills
package already targets core `FoundationModels.Tool` — one tool ecosystem end to end.
The trade: the FM interop path delegates KV-cache management to FoundationModels, so
Router-level `fork()` prefix reuse is unavailable to agent runs, and the Router's
structural transcript recording doesn't see them — the runner records instead (§9).

Every run has a **`workingDirectory`** (defaults to its recording directory, override per
run) for cooperative filesystem isolation between concurrent agents — the same model as
Router sessions.

### 7.1 Agents ↔ runs ↔ sessions — the object model

Three nouns, deliberately distinct — the Router's authored/resolved split, applied to agents:

```
AgentDefinition  (authored file)     static data; no runtime state; one per name
      │  runner.start(name, prompt)
      ▼
AgentRun  (id: ULID)                 ONE delegated task — the unit of identity,
      │  owns; never vends           scheduling, cancellation, recording, and UI
      ▼
LanguageModelSession  (internal)     the run's private generation engine over a
                                     Router slot; born and released with its run
```

- **One definition, many runs.** Concurrent runs of the same agent are fully independent —
  separate sessions, contexts, working directories, transcripts. The run id (not the agent
  name) is the key everywhere at runtime: `check`, `send`, `cancel`, activity rows,
  transcript directories.
- **A run owns exactly one session** for its whole life, and the session is **never
  vended** — the Router's "no side door" rule, applied one level up. Everything crosses the
  run: prompts in, final text out, state observed.
- **A run retains the profile.** The native-session path forgoes the Router's structural
  `RoutedSession.profile` retention, so the run itself retains its environment's
  `LanguageModelProfile` — resident models cannot be evicted mid-run, and the profile frees
  only after every run (and the runner) is released. Same invariant, re-established here.
- **Runs are resumable while retained.** Because the run keeps its session, a follow-up
  continues the same context after `finished` — `run.send(_:)` from Swift, the `send(runId,
  prompt)` action from the model (Claude's resume semantics: a new invocation is fresh;
  resuming a run keeps its full history). Releasing the run releases the session and its
  context; a released or cancelled run's id draws a clear "gone" error, not a silent
  restart.
- **Root sessions are peers, not parents.** The runner exists independently of any root
  session; several root sessions — or plain host code — can share one runner. The
  `AgentsTool` is just a view of the runner from inside a session, and a run never holds a
  reference back to whoever started it.

## 8. Parallelism — the scheduler

**`AgentRunner`** (actor) owns every `AgentRun`:

- **Fair FIFO admission** — at most `maxConcurrentAgents` runs in flight; excess `start`s
  queue on a fair async semaphore (the same primitive the Router uses for forks and its
  per-model serial gate).
- **Two invocation styles through `AgentsTool`:**
  - **`run(agent, prompt)`** — *foreground*: the tool call awaits completion and returns the
    final text. Parallelism still happens when the root model emits **several `run` calls in
    one turn** — FM executes parallel tool calls concurrently. *(Confirm parallel tool-call
    execution against the shipping WWDC26 SDK — decision #12.)*
  - **`start(agent, prompt)` → runId; `check(runId)`; `send(runId, prompt)`;
    `cancel(runId)`** — *background*: the tool returns immediately with a ULID run id; the
    root keeps working and polls `check`, which reports state and, when finished, the final
    text. `send` continues a retained run's session with a follow-up (§7.1). A definition
    with `background: true` is *always* dispatched this way, even via `run`.
- **Host-driven fan-out** needs no root session at all: `runner.start(_:prompt:)` from
  Swift returns an `AgentRun` handle to await — many handles, structured concurrency,
  `TaskGroup`-friendly.
- **Cancellation** is structured: cancelling an `AgentRun` cancels its session's Swift task;
  `cancel(runId)` does it from the model side; runner teardown cancels everything.
- **Observability** — the runner publishes an `@MainActor @Observable` **`AgentActivity`**
  for direct SwiftUI binding — the `ResolutionProgress` pattern, applied to the fleet (§8.1).
- **Honesty clause:** concurrent runs on the *same* slot interleave at the Router's
  per-model serial gate (one generation at a time per resident model); true overlap comes
  from spreading agents across `standard` and `flash`. The scheduler makes multitasking
  *correct and bounded*; the hardware decides how simultaneous it is.

### 8.1 SwiftUI observability — per profile

A runner is bound to **one resolved `LanguageModelProfile`** (the Router's
one-active-profile rule), so per-runner **is** per-profile: `runner.activity` is that
profile's agent dashboard. It is `@MainActor @Observable`, bound straight into SwiftUI:

```swift
@MainActor @Observable
final class AgentActivity {
  let profileName: String                  // the resolved profile this fleet runs on
  var runs: [AgentRunSnapshot] = []        // live + recently finished, newest first
  var lanes: [ModelSlot: SlotLane] = [:]   // the per-model serial gates, visualized
}

struct AgentRunSnapshot: Identifiable, Sendable {
  let id: ULID                             // run id — the row identity
  let agent: String                        // definition name
  let color: AgentColor?                   // frontmatter `color:` — consumed here
  let slot: ModelSlot
  var state: AgentRunState                 // queued → running → finished/failed/cancelled
  var startedAt: Date?; var finishedAt: Date?
  var tokensIn: Int; var tokensOut: Int    // as reported by the FM session
  var lastEvent: String?                   // e.g. "calling tool grep…" for a live row
}

struct SlotLane: Sendable {                // one resident model = one serial lane
  var generating: ULID?                    // the run holding the gate right now
  var queued: [ULID]                       // waiting on this slot, FIFO
}
```

- **Lanes make the honesty clause visible.** Each slot's serial gate is drawn as a lane —
  one run generating, the rest queued behind it — so the UI shows *why* a run is waiting
  instead of an unexplained spinner.
- The `color:` frontmatter field (tier 2, data-only in the registry) is **consumed here**:
  each agent gets its stable badge color in the run list — exactly its Claude Code role.
- Snapshots are value types published on the main actor after each state transition and
  turn; SwiftUI list diffing stays cheap, and a host can keep old snapshots as history.
- **Profiles over an app's lifetime are sequential** (release one, resolve the next — the
  Router rule), so runners are too: one runner, one profile, one `AgentActivity`. A
  profile-switching UI is two dashboards in succession, not one merged view.

### 8.2 Agent events in the calling session's transcript

The agent system is just a tool — but its result is a **special tool result**. Every
`AgentsTool` action returns a **typed `AgentEvent`**, never prose:

```swift
@Generable enum AgentEvent {           // the tool's output type — structured, not text
  case started(runId: ULID, agent: String, slot: ModelSlot)
  case running(runId: ULID, lastEvent: String?)
  case finished(runId: ULID, result: String)
  case failed(runId: ULID, reason: String)
  case sent(runId: ULID)               // follow-up accepted; result via a later check
  case cancelled(runId: ULID)
  case gone(runId: ULID)               // released/unknown id — §7.1's clear error
}
```

FoundationModels records every tool call and its output as transcript entries built from
**segments**, so these events land in the calling session's `Transcript` as **structured
segments** — the custom-segment pattern — rather than dissolving into a text blob:

- **Lifecycle is first-class in the caller's transcript.** `start` writes a `started`
  segment (runId, agent, slot) at the moment of delegation; the `check`/`send` that harvests
  the outcome writes `finished`/`failed`. Replaying the calling transcript reconstructs the
  delegation timeline — who was started, when, on what, and how each ended — without
  parsing prose. A transcript UI renders agent chips/timeline straight from the segments.
- **The model reads the same structure.** Tool output is model-visible, so the root model
  sees unambiguous typed state (`running` vs `finished(result:)`) instead of guessing from
  wording — which is what makes `check`-based multitasking reliable.
- **Honesty about timing:** a tool can only write to the transcript inside its own call, so
  a *background* run's completion appears in the caller's transcript at the harvesting
  `check`/`send` — the live, continuous view is `AgentActivity` (§8.1); the calling
  transcript records the **interaction points**. A finished run's final text enters the
  caller's context exactly once, as that harvesting event's `result`.
- **The two records cross-link.** The caller's `started` segment carries the runId; the
  run's own `transcript.jsonl` (§9) carries the same runId — caller timeline and sub-agent
  detail join on it.
- *(Confirm against the shipping WWDC26 SDK how structured tool output is represented in
  `Transcript` segments — same verification item as Skills decision #18.)*

## 9. Recording & diagnostics

- Every run is recorded: the runner takes a recordings root and writes one
  `agents/<runId>/transcript.jsonl` per run — **same JSONL shape as the Router's** events
  (`{ runId, agent, slot, model, seq, ts, kind: "prompt"|"response"|"toolCall"|"toolOutput", … }`),
  sourced from the FM session's `Transcript` after each turn. ULID run ids keep the tree
  time-sortable. Best-effort, off the hot path, `.jsonl` / `.inMemory` / `.none` sinks —
  the Router's recording philosophy, re-applied where its structural chokepoint can't reach.
- **Diagnostics are data:** the registry exposes `[AgentDiagnostic]` (duplicate names,
  invalid frontmatter, unsupported fields, unknown tools/skills, unmappable models) so a
  host can render a doctor view; nothing valid is blocked by something invalid next to it.

## 10. Cross-repo prerequisites

This plan **supersedes** two assumptions in the sibling plans:

1. **FoundationModelsSkills** — its decision #17 / milestone M7 originally placed the future
   `AgentRegistry` *inside* the Skills target. It now lives **here** instead, and the Skills
   plan has been updated to match (its decisions #17 and #19, and M1): Skills exports
   `FrontmatterDocument` and `FolderStack` as public API, and `FolderStack`'s `EntryKind`
   supports **file-shaped entries** (flat `*.md`, recursive scan) alongside directory-shaped
   ones (`name/SKILL.md`). Sequencing: our M1 needs Skills M1–M2 done.
2. **FoundationModelsRouter** — its plan marked FoundationModels interop "available but not
   load-bearing." It is load-bearing now: the Router must expose a routed slot as an FM
   `LanguageModel` (e.g. `RoutedLLM.foundationModel` or
   `makeLanguageModelSession(tools:instructions:)` via `MLXLanguageModel`), so agent runs
   inherit residency, the per-model serial gate, and provenance. A small, additive change.

Packaging: **single SwiftPM target `FoundationModelsAgents`**, depending on
`FoundationModelsRouter` and `FoundationModelsSkills` (both as local/sibling packages during
development). macOS 27+, Swift 6.1 tools, same platform commitment as the Router — no
fallback paths.

## 11. Resolved decisions

1. **FM entry point → one `AgentsTool`** with **list / run / start / check / send / cancel**
   actions, on core `FoundationModels.Tool` — the Skills single-tool pattern.
2. **Identity → frontmatter `name`** (Claude rule; agents are single files), validated
   lowercase+hyphens; full-replace override by name up the stack; duplicate-in-root ⇒
   diagnostic.
3. **Format → Claude-compatible subset**, three tiers: enforced (`name`, `description`,
   `tools`, `disallowedTools`, `model`, `skills`, `maxTurns`, `background`), data-only
   (`color`, unknown keys), diagnosed-unsupported (`permissionMode`, `mcpServers`, `hooks`,
   `memory`, `effort`, `isolation`, `initialPrompt`).
4. **Body → literal system prompt.** No argument/shell/Stencil rendering; the dynamic input
   is the task prompt.
5. **Models → slot-mapped**: `standard` / `flash` / `inherit` canonical; Claude aliases map
   (`opus`/`sonnet`/`fable` → standard, `haiku` → flash) via an overridable `ModelMapping`;
   literal model ids draw a diagnostic and fall back to `inherit`.
6. **Execution → native `LanguageModelSession`** over Router-resident models via
   `MLXLanguageModel` — Apple drives the tool loop; `RoutedSession` stays the no-tools
   generation surface. Fork-style KV reuse is explicitly given up for agent runs.
7. **Tools → host `ToolCatalog`**; omit = inherit all; `disallowedTools` then `tools`
   (Claude order); unknown names diagnosed. No nested agents in v1.
8. **`skills:` preload → rendered bodies appended to instructions** at run start, via an
   optional `SkillsRegistry` (full content, Claude semantics).
9. **`maxTurns` → counting tool decorator**; crossing the bound cancels the run.
10. **Parallelism → `AgentRunner` actor** with fair FIFO admission (`maxConcurrentAgents`),
    structured cancellation, background runs by id, `@Observable AgentActivity` for UI.
    Per-model serialization acknowledged, not hidden.
11. **Recording → per-run JSONL** in the Router's event shape, from the FM `Transcript`,
    best-effort; `.jsonl` / `.inMemory` / `.none`.
12. **Foreground parallel `run` relies on FM parallel tool-call execution.** *(Confirm
    against the shipping WWDC26 SDK; if tool calls execute serially, the `start`/`check`
    path is the parallel primitive and `run` stays correct, just sequential.)*
13. **Layer reuse → depend on FoundationModelsSkills** for `FrontmatterDocument` +
    `FolderStack` (with the file-entry generalization) — superseding Skills decision #17's
    same-target `AgentRegistry`.
14. **Packaging → single SwiftPM target**, macOS 27+ / Swift 6.1, sibling-package
    dependencies on Router and Skills.
15. **Object model → definition ≠ run ≠ session** (§7.1). `AgentDefinition` is data;
    `AgentRun` is the unit of identity/scheduling/recording/UI, **owns exactly one
    never-vended session**, and **retains the profile** (the Router's residency invariant,
    re-established one level up). Runs are **resumable while retained** — `run.send(_:)` /
    the `send` action continue the same context; release frees session and context.
16. **Observability → per-profile `AgentActivity`** (`@MainActor @Observable`, §8.1): one
    runner per resolved profile, run snapshots + per-slot **lanes** that visualize the
    serial gates; the `color:` field is consumed here for stable agent badges. Sequential
    profiles ⇒ sequential runners ⇒ one dashboard each.
17. **Calling-transcript events → typed `AgentEvent` tool output** (§8.2). The agent system
    is just a tool, but its result is a *special tool result*: every action returns a
    `@Generable AgentEvent` (`started` / `running` / `finished` / `failed` / `sent` /
    `cancelled` / `gone`) that lands in the calling session's `Transcript` as a structured
    segment — lifecycle first-class in the caller's record, model-visible, UI-renderable.
    Background completions surface at the harvesting `check`/`send`; live state is
    `AgentActivity`'s job. *(Confirm segment representation against the shipping WWDC26
    SDK.)*

## 12. Public API sketch (illustrative)

```swift
// Layer 3 — stacked, watched, validated definitions:
let agents = try AgentRegistry(
  roots: [userAgentsURL, projectAgentsURL],   // low → high; full-replace by name
  watch: true
)
agents.diagnostics                             // [AgentDiagnostic] — doctor view

// The execution environment — models from the Router, tools from the host:
let env = AgentEnvironment(
  profile: profile,                            // resolved LanguageModelProfile
  defaultSlot: .flash,                         // what `inherit` means here
  modelMapping: .default,                      // Claude aliases → slots
  tools: catalog,                              // ToolCatalog: name → Tool factory
  skills: skillsRegistry,                      // optional: powers `skills:` preload
  maxConcurrentAgents: 4,
  recordingsDir: recordingsURL
)
let runner = AgentRunner(registry: agents, environment: env)

// Host-driven fan-out — no root session required:
let run = try await runner.start("code-reviewer", prompt: "Review:\n\(diff)")
let report = try await run.result()            // final text; run.state observable
let more   = try await run.send("Now check the tests too")   // same session, same context
// Many at once, bounded by admission:
async let a = runner.start("code-reviewer", prompt: p1).result()
async let b = runner.start("test-writer",   prompt: p2).result()

// Layer 4 — model-driven delegation from a root session:
let agentsTool = AgentsTool.builder(runner: runner)
  .actions([.list, .run, .start, .check, .send, .cancel])
  .build()
let root = LanguageModelSession(
  tools: [agentsTool, skillsTool.tool],
  instructions: Instructions { "…base instructions…" }
)
// The root model now sees each agent's name + description and delegates:
// run("code-reviewer", "Review the diff …") → sub-agent's final text as tool output.

// Per-profile fleet observability for SwiftUI (§8.1):
@State var activity = runner.activity          // @MainActor @Observable AgentActivity
// activity.runs → rows; activity.lanes[.standard] → who's generating vs queued
```

Core types: `AgentDefinition` (parsed file), `AgentListing` (metadata view: name,
description, slot, tools, color, provenance), `AgentRegistry`, `AgentEnvironment`,
`ToolCatalog`, `ModelMapping`, `AgentRunner` (actor), `AgentRun` (handle: `id: ULID`,
`state`, `result()`, `send(_:)`, `cancel()`), `AgentRunState` (`queued`, `running`,
`finished(String)`, `failed(AgentRunFailure)`, `cancelled`), `AgentActivity`
(`@MainActor @Observable`; `AgentRunSnapshot`, `SlotLane`, `AgentColor` — §8.1),
`AgentDiagnostic`.

## 13. Milestones

- **M1 — Definition parsing + validation.** `AgentDefinition` on `FrontmatterDocument`:
  frontmatter tiers, name validation, tool-list parsing, model mapping (pure). *(Needs
  Skills M1.)*
- **M2 — `AgentRegistry` on `FolderStack`.** Stacked roots, recursive file entries,
  full-replace precedence, duplicate diagnostics, watch/reload, `listing()`. *(Needs Skills
  M2 + the file-entry generalization.)*
- **M3 — Execution substrate.** Router interop (`RoutedLLM` → FM `LanguageModel`); one
  `AgentRun` end to end: instructions + resolved tools + slot → native session → final text.
  *(Needs the Router interop addition.)*
- **M4 — `AgentsTool`.** list/run on core `FoundationModels.Tool`; typed `AgentEvent`
  output landing as structured segments in the calling transcript (§8.2); live-registry
  deref with stale-name backstop; delegation proven from a root session.
- **M5 — Scheduler + observability.** `AgentRunner` admission gate, background
  `start`/`check`/`send`/`cancel`, structured cancellation, resumable runs (§7.1);
  `AgentActivity` with run snapshots + slot lanes (§8.1); `background: true` routing.
- **M6 — Semantics fill-in.** `skills:` preload, `disallowedTools` order, `maxTurns`
  decorator, model-mapping diagnostics, workingDirectory isolation.
- **M7 — Recording + polish.** Per-run JSONL transcripts, diagnostics surface, docs +
  examples (a review fan-out sample app).

## 14. Testing

Unit-testable pieces (frontmatter tiers, identity/precedence, tool-list resolution, model
mapping, maxTurns decorator, scheduler admission/cancellation) take injected definitions and
**stub sessions** — no models, covered per milestone. Registry tests run against fixture
directory stacks; watcher tests against temp dirs.

A separate **gated integration suite** (Swift Testing, `.serialized`, opt-in env var —
the Router's pattern, tiny `mlx-community` models) proves: a definition file becomes a live
sub-agent; delegation from a root session round-trips (root → `AgentsTool.run` → sub-agent
tool use → final text back); two concurrent runs on different slots make progress
independently; `check`/`cancel` behave; a `send` follow-up continues a run's context; the
calling session's transcript carries the run's `started`/`finished` structured segments
(§8.2); a run's `transcript.jsonl` lands under its run id.

---

### Sources
- Claude Code sub-agents — https://code.claude.com/docs/en/sub-agents
- FoundationModelsRouter plan — ../FoundationModelsRouter/plan.md
- FoundationModelsSkills plan — ../FoundationModelsSkills/plan.md
- What's new in Foundation Models (WWDC26) — https://developer.apple.com/videos/play/wwdc2026/241/
- Build agentic app experiences with Foundation Models (WWDC26) — https://developer.apple.com/videos/play/wwdc2026/242/
