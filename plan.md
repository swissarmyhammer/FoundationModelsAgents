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
  through one tool — `AgentsTool`, a **fused `OperationTool`** named `agents` (the sah
  operation pattern via `../FoundationModelsOperationTool`, §10) whose six ops share
  **one noun**: `list agents` / `search agents` / `start agent` / `check agent` /
  `send agent` / `cancel agent` — all delegation is *background* (§8).
  The framework has no agents concept; we add a *tool*, not a new primitive. This mirrors
  Claude Code, where delegation happens through the `Agent` (né `Task`) tool. But it is a
  **special tool result**: every lifecycle op returns a typed `AgentEvent` that
  lands in the calling session's transcript as a structured segment (§8.2; the catalog
  ops `list agents`/`search agents` return listings — the §8 op table), so agent
  starts/stops are first-class
  entries in the caller's record, not prose.
- **One session system, one recording system.** An agent is a *utility that drives
  activity in a session*. Every run is a **Router session** — a child in the Router's
  lineage-nested recording tree — so there is exactly one transcript model, one event
  vocabulary, and one thing to observe: **the session** (§7, §8.3, §9).
- **A sub-agent is a fresh, isolated session — a *routed* one.** Each run gets its own
  tool-capable `RoutedSession`: its own context, its own system prompt (the definition
  body), its own tool set, its own working directory. It sees only the task prompt the
  caller composed — never the parent's context (unless deliberately *forked*, §7). Only its
  **final text** returns to the caller.
- **Definition ≠ run ≠ session.** An `AgentDefinition` is authored data; an `AgentRun` is
  one delegated task — the unit of scheduling, cancellation, and UI — and it **drives**
  exactly one session, which is never vended (§7.1). The run's id **is** its session's id.
  One definition, many concurrent runs; follow-ups go through the run, whose session (and
  context) lives as long as the run handle.
- **Descriptions are the delegation contract.** Agent catalogs are usually small (unlike
  skills), so each agent's `name` + `description` are baked directly into the `AgentsTool`
  surface — the root model reads them to decide when and where to delegate. When a
  deployment's catalog outgrows the baked-in surface, the model narrows it with
  **`search agents`** — ranked lexical retrieval (BM25 + trigram, RRF-fused) over
  `name` + `description`, powered by
  [`../FoundationModelsRanker`](../FoundationModelsRanker/plan.md) (§8, §10).
  *(Supersedes the earlier reservation of `MetadataSearcher<AgentListing>` from
  FoundationModelsMetadataRegistry for this role — the retrieval primitives now come
  from the Ranker directly; no separate search agent, no registry detour.)*
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
│   AgentsTool — one fused OperationTool "agents": list agents /             │
│                search agents / start agent / check agent / send agent /    │
│                cancel agent                                                │
│   AgentRunner — actor: parallel runs, fair admission, cancellation         │
│   AgentRun — drives ONE RoutedSession (run id = session id); state, result │
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
  **Model-free**: the registry is pure files + validation; the Router never enters here
  (§6's mapping produces a *slot name*, not a model).
- **FM adapter** (Layer 4) — `AgentsTool` (one fused `OperationTool` from
  `FoundationModelsOperations` — §8's op table, §10's dependency), `AgentRunner`,
  `AgentRun`, all reading the registry and executing over Router-vended models. **The Router enters exactly once,
  through `AgentEnvironment.profile`** — a Router-resolved `LanguageModelProfile` (§7, §12);
  everything model-shaped flows from that one handle.

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
  publishes refreshed metadata — parity with Claude Code, which live-watches its agent
  directories too (a restart is needed there only for a scope's brand-new agents
  directory; the FolderStack watcher covers newly created roots as well).

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
| **1 — enforced** | `name`, `description` (required); `tools`, `disallowedTools`; `model`; `skills`; `maxTurns` | Full semantics (§5–§7) |
| **2 — data only** | `color`; `background` (every run is background here — `true` is redundantly satisfied, `false` cannot be honored and draws a diagnostic, §8); plus all unrecognized `metadata`-style keys | Exposed on `AgentListing` for hosts/UI; no behavior |
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
  `tools` is resolved against the remainder; a tool named in both is removed. **MCP
  server patterns** (`mcp__<server>`, `mcp__<server>__*`, `mcp__*`) are honored as
  prefix matches against catalog names — Claude's grammar, so a Claude-authored
  `disallowedTools: mcp__github` denies exactly what its author meant. Parenthesized
  `Agent(...)` entries parse but draw a diagnostic (no nested agents in v1). Other
  unknown tool names ⇒ diagnostic, skipped — except an unresolvable `disallowedTools`
  entry, which is escalated to a **loud** diagnostic: silently dropping a *deny* would
  grant more than the author intended.
- **No nested agents in v1.** The `AgentsTool` is never placed in a sub-agent's tool set,
  and a definition listing it draws a diagnostic. (Claude allows depth 5; we start at 1 —
  a depth-limited nesting option is a clean later extension.)
- **`skills:` preload — a formal Skills dependency.** The environment carries a
  `SkillsRegistry` (non-optional; an empty registry is fine), and each listed skill's
  **rendered body** is appended to the sub-agent's instructions at run start (full content,
  not just the description — Claude's `skills` semantics). Missing or
  `disable-model-invocation` skills are skipped with a diagnostic. This is the second half
  of the Skills dependency: layers 1–2 for the definition stack (§2), `SkillsRegistry` for
  preload (§10).
- **`maxTurns`** — FM's session runs its tool loop inside one `respond` call, so we enforce
  the bound structurally: every tool handed to the run is wrapped in a **counting decorator**;
  when the count crosses `maxTurns` the run is cancelled and reports
  `.failed(hitMaxTurns)`. Best-effort but real — no tool call escapes the wrapper.
  *Deliberate divergence:* Claude counts **agentic turns** and quietly stops; we count
  **tool calls** — strictly tighter, since one turn can hold several parallel calls —
  and surface the stop as a failure. `hitMaxTurns` carries any partial text produced so
  far, for the closest available parity with Claude's stop-with-partial-output.

## 6. Model mapping — frontmatter → Router slot

A resolved `LanguageModelProfile` supplies the models; the definition picks a slot:

| `model:` value | Resolves to |
|---|---|
| *(omitted)* / `inherit` | **the caller's slot** — the bound calling session's slot (decision #19), which is exactly Claude's "the main conversation's model"; a host-driven run with no caller resolves to `.standard` |
| `standard` *(ours, canonical)* | `profile.standard` |
| `flash` *(ours, canonical)* | `profile.flash` |
| `opus`, `sonnet`, `fable` *(Claude aliases)* | `profile.standard` |
| `haiku` *(Claude alias)* | `profile.flash` |
| full model id (e.g. `claude-opus-4-8`, an HF repo) | **diagnostic; falls back to `inherit`** — picking repos is the Router's job, not a definition's |

The alias table lives in a `ModelMapping` value (default above, host-overridable), so a
Claude-authored agent file runs unmodified while our canonical vocabulary stays
slot-shaped.

*Deliberate divergence:* Claude's full resolution order also honors a
`CLAUDE_CODE_SUBAGENT_MODEL` environment variable and a per-invocation `model` parameter
on its Agent tool, both outranking frontmatter. Neither exists here — the frontmatter
slot and the caller-derived `inherit` are the whole story; per-run model steering is the
profile's job, not the caller's.

## 7. Execution — one run drives one routed session

`AgentRun` is one delegated task:

1. **Resolve** the agent from the live registry (stale name ⇒ error carrying the current
   listing, same backstop pattern as `SkillsTool.call`).
2. **Assemble** instructions = definition body + rendered `skills:` preloads; tools = §5
   resolution, each wrapped in the counting decorator; model = §6 slot.
3. **Spawn** a **tool-capable `RoutedSession`** over the slot's resident model (§10's Router
   growth) with the assembled instructions and tools, and submit the caller's task prompt.
   The FM tool loop (via the `MLXLanguageModel` interop) runs *inside* the session's
   recorded chokepoint — every prompt, response, `toolCall`, and `toolOutput` is a recorded
   session event.
4. **Return** the session's final text as the run's result. Tool traffic, intermediate
   turns, and context stay inside the run.

*Deliberate divergence — startup context:* Claude additionally injects the CLAUDE.md /
memory hierarchy and a git-status snapshot into a non-fork sub-agent's initial context, so
Claude-authored prompts may assume project rules reach the sub-agent. Here a spawned run
receives **only** body + `skills:` preloads + task prompt — nothing ambient. A host
wanting parity folds shared context in explicitly (a `skills:` preload or the task
prompt); we never inject silently.

**Agent runs are Router sessions — not a parallel session system.** The session is the unit
of recording, lineage, residency, and observation; the agent is a utility that drives
activity in it:

- **Lineage is delegation.** A run started from a routed calling session is a **child
  session** — `parentId` = the caller, recording directory nested under the caller's — so
  the Router's on-disk session tree *is* the delegation tree. A host-driven run with no
  calling session is a root session under the Router. The mechanism is
  **construction-time binding**: FM hands a tool no context object (arguments only,
  decision #19), so an `AgentsTool` cannot *discover* its caller — the Router's
  tool-capable `makeSession(tools:)` binds its own session id into the `AgentsTool` it
  hosts (the §5 factory pattern), and a host-built tool takes an explicit `caller:`
  (nil ⇒ its runs are roots).
- **Two child flavors.** **`spawn`** — fresh context: own instructions (the agent body),
  own tools, empty cache — the named-agent case. **`fork`** — inherits the caller's context
  and prefilled KV prefix — Claude's fork-the-conversation case, which also recovers KV
  prefix reuse for template fan-outs. Both are children in one tree; both queue at the
  Router's admission gate, and creating either **appends an anchor entry to the parent
  at its current tip** (§8.4). A fork's transcript is a **continuation**: it records only
  entries after the fork point (a `forkedFrom` marker names the parent entry); the
  inherited prefix stays reachable through the parent, never copied (§8.4).
- **Recording is structural, once.** Sessions are born holding the Router's recorder; the
  bracketed chokepoint sees the whole tool loop. No agents-side recording system exists (§9).

This requires the Router to grow (§10): tool-capable sessions, a `spawn` sibling to
`fork()`, and a live event tap on the recorder. *(Engineering risk: reconciling the
session-owned KV cache with an FM-driven tool loop. Worst case, tool-capable sessions
delegate cache management to FM and lose `fork()` KV reuse on those sessions — while
recording, lineage, residency, and the gates still unify. Verify against the shipping
WWDC26 SDK.)*

Every run's session has the Router's **`workingDirectory`** semantics — defaults to its
recording directory, overridable per run — for cooperative filesystem isolation between
concurrent agents.

### 7.1 Agents ↔ runs ↔ sessions — the object model

Three nouns, deliberately distinct — the Router's authored/resolved split, applied to agents:

```
AgentDefinition  (authored file)     static data; no runtime state; one per name
      │  runner.start(name, prompt)
      ▼
AgentRun  (id = session id)          ONE delegated task — the unit of scheduling,
      │  drives; never vends         cancellation, and UI
      ▼
RoutedSession  (internal)            the run's engine IN the Router's session and
                                     recording tree; born and released with its run
```

- **One definition, many runs.** Concurrent runs of the same agent are fully independent —
  separate sessions, contexts, working directories, transcripts. The run id **is the
  session id** — one ULID is the `id` in `check agent`/`send agent`/`cancel agent`, the activity row, and
  the session's transcript directory in the Router tree.
- **A run drives exactly one session** for its whole life, and the session is **never
  vended** — the Router's "no side door" rule holds. Everything crosses the run: prompts
  in, final text out; the session itself is what gets recorded and observed (§8.3, §9).
- **Residency is structural.** A `RoutedSession` retains its profile — the Router's own
  invariant — so resident models cannot be evicted mid-run, with nothing re-established at
  the agents layer.
- **Runs are resumable while retained.** Because the run keeps its session, a follow-up
  continues the same context after `finished` — `run.send(_:)` from Swift, the `send agent`
  op from the model (Claude's resume semantics: a new invocation is fresh;
  resuming a run keeps its full history). Releasing the run releases the session and its
  context; a released or cancelled run's id draws a clear "gone" error, not a silent
  restart.
- **Root sessions are peers, not parents.** The runner exists independently of any root
  session; several root sessions — or plain host code — can share one runner. The
  `AgentsTool` is just a view of the runner from inside a session, and a run never holds a
  reference back to whoever started it. Notification turns (§8.5) don't change this: the
  *runner* delivers them through the Router by caller id; the run itself holds nothing.

## 8. Parallelism — the scheduler

**`AgentRunner` is the scheduler and registrar for delegation** — the actor that turns a
named agent + a prompt into a bounded, cancellable, findable routed session, and the
bookkeeper that remembers which runs exist, who asked for them, and who to wake when
they finish. It is *not* a session system, an agent loop, a display surface, or a
recorder — every run it makes is a Router session it asked for; delegation semantics
live here, session substrate lives in the Router. It owns every `AgentRun`:

- **Fair FIFO admission** — at most `maxConcurrentAgents` runs in flight; excess
  `start agent` calls queue on a fair async semaphore (the same primitive the Router uses for forks and its
  per-model serial gate).
- **One invocation style — background only.** **`start agent` → `started(id)`**: the tool
  returns immediately with the ULID agent id (= session id); the calling session is never
  parked on a delegation. The root keeps working and polls **`check agent`**, which reports
  state and, when finished, the final text; **`send agent`** continues a retained run's
  session with a follow-up (§7.1); **`cancel agent`** stops it. There is deliberately
  **no foreground op**: an awaiting tool call would block the calling session for the
  sub-agent's whole lifetime — the moment two things should happen at once, foreground is
  the wrong default — and one dispatch path keeps the model's job simple: start, keep
  working, check. *(Deliberate divergence: Claude offers both styles and — ≥2.1.198 —
  already defaults unset-`background` to background; we take that to its conclusion.
  `background:` frontmatter is accepted: `true` is redundantly satisfied, `false` cannot
  be honored and draws a diagnostic. FM's parallel tool-call behavior is no longer
  load-bearing — multitasking is many started runs, not parallel awaits — decision #12.)*
- **Host-driven fan-out** needs no root session at all: `runner.start(_:prompt:)` from
  Swift returns an `AgentRun` handle to await — many handles, structured concurrency,
  `TaskGroup`-friendly.
- **Cancellation** is structured: cancelling an `AgentRun` cancels its session's Swift task;
  `cancel agent` does it from the model side; runner teardown cancels everything.
- **Observability** — the runner publishes an `@MainActor @Observable` **`AgentActivity`**
  for direct SwiftUI binding — the `ResolutionProgress` pattern, applied to every live
  agent (§8.1).
- **Honesty clause:** concurrent runs on the *same* slot interleave at the Router's
  per-model serial gate (one generation at a time per resident model); true overlap comes
  from spreading agents across `standard` and `flash`. The scheduler makes multitasking
  *correct and bounded*; the hardware decides how simultaneous it is.

### The op vocabulary

The whole `AgentsTool` surface in one table (the Shelltool-plan convention): one fused
`OperationTool` named **`agents`** — `@Generable @Operation` structs, `op: "verb noun"`
dispatch from `FoundationModelsOperations` (§10) — six ops sharing **one noun,
`agent`**, all background; every parameter is named here and nowhere else. A `name`
addresses a definition; an `id` addresses a live run. Lifecycle ops return typed
`AgentEvent`s (§8.2); the catalog ops — `list agents`, `search agents` — return
`[AgentListing]`:

| op | parameters | returns | behavior |
|---|---|---|---|
| `list agents` | *(none)* | `[AgentListing]` | The delegation surface, live from the registry: each agent's `name`, `description`, slot, `color`. The same words the frontmatter authored — hot reload refreshes them (§15). |
| `search agents` | `query` (req), `limit?` | `[AgentListing]` | The same live listings, **ranked**: BM25 + trigram over `name` (primary field) + `description` (body), RRF-fused — `FoundationModelsRanker` (§10). Lexical by default (no model, no embedder); cosine joins the fusion when the profile provides an embedder. The in-memory index rebuilds from the registry's reload publication (§15). |
| `start agent` | `name` (req), `prompt` (req) | `started(id, name, slot)` | Returns immediately with the ULID agent id (= session id); the run proceeds under the admission gate while the caller keeps working. Unknown/stale `name` ⇒ error carrying the current listing. |
| `check agent` | `id?` | one event — or one per agent | With `id`: `running(id, lastEvent)` / `finished` / `failed` / `cancelled` / `gone`. The **sole harvest point**: a finished agent's final text enters the caller's context exactly once, in this `finished` event (§8.2). With `id` omitted ⇒ **all agents**: one event per live or unharvested run — in-flight agents report `running`, ready completions are harvested in the same call. Released/unknown `id` ⇒ `gone`. |
| `send agent` | `id` (req), `prompt` (req) | `sent(id)` / `gone` | Follow-up into a retained run's **same session and context** (§7.1 resume semantics). `sent` deliberately carries no result — it arrives via a later `check agent`. |
| `cancel agent` | `id` (req) | `cancelled(id)` / `gone` | Structured cancellation of the run's session task; the record keeps everything captured so far (§9). |

The operations package's forgiving resolver supplies verb aliases (`prompt agent` →
`send agent`, `stop agent` → `cancel agent`, `find agents` → `search agents`) without
widening the real vocabulary.

### 8.1 SwiftUI observability — per profile

A runner is bound to **one resolved `LanguageModelProfile`** (the Router's
one-active-profile rule), so per-runner **is** per-profile: `runner.activity` is that
profile's agent dashboard. It is `@MainActor @Observable`, bound straight into SwiftUI:

```swift
@MainActor @Observable
final class AgentActivity {
  let profileName: String                  // the resolved profile these agents run on
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
  var lastEvent: String?                   // "calling tool grep…" — the run's transcript tail (§8.3)
}

struct SlotLane: Sendable {                // one resident model = one serial lane
  var generating: ULID?                    // the run holding the gate right now
  var queued: [ULID]                       // waiting on this slot, FIFO
}
```

- **Lanes make the honesty clause visible.** Each slot's serial gate is drawn as a lane —
  one run generating, the rest queued behind it — so the UI shows *why* a run is waiting
  instead of an unexplained spinner.
- **Scheduler facts live here; content lives in transcripts.** Lanes, queue position, and
  admission are runner state that appears in *no* transcript; a card's content — the
  one-liner, the drill-in — comes from observing `run.transcript` (§8.3, §8.4). One
  dashboard, two sources, no duplication.
- The `color:` frontmatter field (tier 2, data-only in the registry) is **consumed here**:
  each agent gets its stable badge color in the run list — exactly its Claude Code role.
- Snapshots are value types published on the main actor after each state transition and
  turn; SwiftUI list diffing stays cheap, and a host can keep old snapshots as history.
- **Profiles over an app's lifetime are sequential** (release one, resolve the next — the
  Router rule), so runners are too: one runner, one profile, one `AgentActivity`. A
  profile-switching UI is two dashboards in succession, not one merged view.

### 8.2 Agent events in the calling session's transcript

The agent system is just a tool — but its result is a **special tool result**. Every
lifecycle op returns a **typed `AgentEvent`**, never prose (the catalog ops
`list agents`/`search agents` return `[AgentListing]` — the §8 op table):

```swift
@Generable enum AgentEvent {           // the tool's output type — structured, not text
  case started(id: ULID, name: String, slot: ModelSlot)
  case running(id: ULID, lastEvent: String?)
  case finished(id: ULID, result: String)
  case failed(id: ULID, reason: String)
  case sent(id: ULID)                  // follow-up accepted; result via a later check
  case cancelled(id: ULID)
  case gone(id: ULID)                  // released/unknown id — §7.1's clear error
}
```

FoundationModels records every tool call and its output as transcript entries built from
**segments**, so these events land in the calling session's `Transcript` as **structured
segments** — the custom-segment pattern — rather than dissolving into a text blob:

- **Lifecycle is first-class in the caller's transcript.** `start agent` writes a `started`
  segment (id, name, slot) at the moment of delegation — a **self-sufficient card
  seed**: a UI renders the agent card shell from this one entry with zero lookups, and
  the entry's `child` provenance (§8.4) is the *same ULID* as the segment's `id`, an
  equality the tests assert (only `color` needs a registry lookup, by the name the
  segment already carries). The `check agent` that harvests the
  outcome writes `finished`/`failed`. Replaying the calling transcript reconstructs the
  delegation timeline — who was started, when, on what, and how each ended — without
  parsing prose. A transcript UI renders agent chips/timeline straight from the segments.
- **The model reads the same structure.** Tool output is model-visible, so the root model
  sees unambiguous typed state (`running` vs `finished(result:)`) instead of guessing from
  wording — which is what makes `check agent`-based multitasking reliable.
- **Honesty about timing:** a tool can only write to the transcript inside its own call, so
  a run's completion appears in the caller's transcript at the harvesting
  `check agent` — the live, continuous view is `AgentActivity` (§8.1); the calling transcript
  records the **interaction points**. A finished run's final text enters the caller's
  context exactly once, as that harvesting `finished` event's `result` (`sent` deliberately
  carries none — a follow-up's outcome arrives via its own later `check agent`).
- **The records are one tree.** The `id` in the caller's `started` segment *is* the
  agent's session id, and that session's `transcript.jsonl` is nested under the caller's in
  the Router tree (§9) — caller timeline and sub-agent detail join by lineage, not by
  side-band correlation.
- *(Confirm against the shipping WWDC26 SDK how structured tool output is represented in
  `Transcript` segments — same verification item as Skills decision #18.)*

### 8.3 Live progress — observe the transcript

**The thing to observe is the session — and the way you observe a session is its
transcript.** This is the FM-native idiom: `LanguageModelSession` is itself `@Observable`
with a growing `transcript` property that SwiftUI binds to directly. Routed sessions do
the same: every prompt, response, sub-tool call, and tool output flows through the
Router's recorder chokepoint (typed, totally ordered — the §9 schema) and **appends to an
observable, append-only `Transcript` per session**. `AgentRun.transcript` is the run's
read-only view of it — the session itself is still never vended (§7.1).

- **One append, two views.** The same chokepoint event becomes an entry in the observable
  transcript *and* a line in the session's `transcript.jsonl` (§9) — live observation and
  the durable record carry identical entries, so a UI built on live transcripts replays
  recordings for free. **No separate event stream survives in the public API**; a host
  that wants a stream derives one from observation.
- **The §5 decorator stays for enforcement, not eventing.** `maxTurns` counting rides the
  wrapped tools; tool activity reaches observers through the recorded transcript like
  everything else.
- **The Router's role, stated exactly:** it supplies the resident model, the per-model
  serial gate (why §8.1's `lanes` are truthful), the session itself, **and the nested
  observable transcripts** — lineage (`parentId`) plus the agent-id keys make the set of
  transcripts a navigable tree (§8.4). Nothing about progress lives outside the session
  record model.

### 8.4 Notifications & correlation — the display contract

The library ships no GUI; it ships the **primitives a display needs**, and this is that
contract. Notifications have two audiences with different physics:

- **The calling model** learns things only at *interaction points* — an FM tool writes to
  the transcript inside its own call, and nothing can push into a model's context between
  turns. So the model's notifications are §8.2's typed events: `started` at delegation,
  `running`/`finished` at each `check agent` (id-omitted to re-orient on everything at
  once). A host that wants the model to react promptly to a completion prepends a short
  note to the *next* prompt ("agent 01H… finished — check it"); the library surfaces the
  completion, the host chooses the nudge.
- **The host/UI** observes transcripts — the FM-native way (§8.3): the calling session's
  transcript for the conversation, `run.transcript` for each agent card, all growing
  live; `@Observable AgentActivity` (§8.1) adds the scheduler facts no transcript
  contains — queue position, who holds a slot's gate.

**One ULID correlates everything.** The agent id *is* the session id, and it appears on every
artifact of a run: the `started` segment in the calling transcript (the anchor), the run's
own observable transcript, the `AgentRunSnapshot` row, the harvesting `check agent`'s
`finished`/`failed` segment, and the recording directory in the Router tree. The intended
rendering falls out of that key:

1. the `started` segment anchors **one agent card** at the delegation point in the
   conversation view;
2. observing `run.transcript` updates the card **in place** — its tail entry is the
   one-line `lastEvent` ("calling tool grep…"); `AgentActivity` adds `state` and
   lane/queue chips;
3. **click to drill in**: the same transcript in full — observed live, or replayed
   post-hoc from the lineage-nested `transcript.jsonl` (§9), identical entries either way;
4. the later harvesting `check agent` carries the **same id**, so its `finished` segment folds
   into the existing card as the result line instead of opening a new entry.

**The drill-in walk — the join is positional: entry → nested transcript.** A UI renders
a transcript linearly, entry by entry; what it needs at each step is "did *this* entry
open a session — and if so, hand me its transcript." So that is the API. The Router
knows the child's id at the moment it writes the delegation's `toolOutput` entry (the
spawn happened inside that tool call, §7), and stamps it as recorded provenance:
**`entry.child: ULID?`** — no segment parsing, present in the live transcript and in
the jsonl alike (§9). Resolution is one call, for every child flavor:
**`transcript.nested(at: entry) → Transcript?`**. The whole UI walk:

```swift
for entry in transcript.entries {
  render(entry)
  if let nested = transcript.nested(at: entry) { agentCard(nested) }  // in place
}
```

Ordering is the Router's, for free: session ids are ULIDs (lexicographically
time-sortable, so siblings sort by creation), and the recorder actor assigns `seq`/`ts`
at append — one total order across the whole tree; a session's transcript is a filtered
subsequence of it.

**The anchor is self-sufficient, and attachment has one policy.** A run is born *inside*
the tool call, so it exists before its anchor entry is written. The policy is
**dashboard-first, dock at anchor**: a freshly started run appears in `AgentActivity`
immediately, and docks into the conversation when the delegation's `toolOutput` entry
lands. From the entry side there is no race: by anchor-write time the child already
exists, so **`transcript.nested(at:)` on a `started` anchor never returns nil**, and the
entry alone — typed segment (id, name, slot) plus `child` provenance, one and the
same ULID (§8.2) — seeds the card with zero lookups. `AgentRun` keeps `recordURL` (its jsonl under the caller — nobody
composes recording paths by hand), and the runner keeps a management index (`runs`,
`run(id:)`) for dashboards and cancel-everything — but *display* never needs it:
position comes from the entry itself. This exact walk is an integration test case (§15)
and a dedicated example (`NestedTranscripts`, §13).

**Forks are just children.** Creating any child — a model-started spawn or a
host/Router fork — **appends an anchor entry to the parent at its current tip**: a
delegation's `toolOutput`, or a `fork` event, each carrying `child`. A tool cannot run
retroactively, so anchors only ever appear in order — rendering stays linear, and
attachments show up as the transcript grows, never inserted into the past.
`transcript.nested(at:)` is the one join for both flavors. The difference between them
is the child's *starting context*, not its display: a spawn's transcript starts empty; a
fork's is a **continuation** — it records only post-fork entries, with
`forkedFrom(parentId, seq)` as child-side provenance naming the prefix it inherited
(reachable through the parent, never copied).

Everything about one agent stays together by construction — keyed by one id, joined by
lineage, never by side-band correlation. `AgentDashboard` (§13) demonstrates the contract.

### 8.5 Waiting without blocking — the notification turn

Claude Code's background agents feel like the model is "waiting" while still accepting
messages. That waiting is a **conversational state, not a runtime state**, and it needs
no custom agent loop — three mechanisms, all inside plain `LanguageModelSession`
semantics:

- **Turn discipline is a contract, not machinery.** The `AgentsTool` instructions state
  it: *after starting runs, finish your turn; do not poll; you will be prompted when a
  run completes.* The turn ends, the session goes idle, and idle sessions answer anyone —
  the user's next prompt is an ordinary turn, during which the model handles unrelated
  work or answers "still running" (an id-omitted `check agent` re-orients it).
- **The notification turn.** Nothing can push into a model's context, so "proceeding
  when done" is a new turn someone initiates. The runner initiates it: on a run's
  terminal state it composes a short prompt — "agent 01H… (code-reviewer) finished — check
  it" — and enqueues one `respond(to:)` on the calling session. Not a loop: one
  host-initiated turn per completion event. The model receives it like any message,
  runs `check agent`, harvests, and continues whatever it said it was waiting on.
- **Serialization is the session; coalescing is ours.** FM sessions answer one turn at a
  time, so a notification arriving mid-turn simply queues — the session *is* the
  serializer. The runner **coalesces**: completions that accumulate while the session is
  busy are delivered as one notification turn naming all of them; one id-omitted
  `check agent` harvests the batch.

**Delivery path — the sub-agent never touches the caller.** The run holds no reference
back (§7.1); the *runner* knows every run's caller id (decision #19's binding) and asks
the **Router** — the session owner — to enqueue the prompt by id (§10 growth (d)).
Sessions stay never-vended end to end. A native-`LanguageModelSession` root has no
routed session to prompt, so it takes `.manual` (the host observes and prompts itself) —
the same boundary as positional nesting (§8.4).

Policy lives on the environment — `notifications: .automatic` (default; the behavior
above) / `.manual` / `.none` — and the notification prompt flows through the recorder
chokepoint like any prompt, stamped `notifying: [sessionIds]`, so the transcript shows *why*
the model spoke and a UI renders wakes distinctly from user messages. The full weave is
an integration test case (§15).

## 9. Recording & diagnostics

- **One recording system: the Router's.** An agent run's transcript is its session's
  `transcript.jsonl` in the Router's lineage-nested tree
  (`recordings/<routerId>/<caller…>/<sessionId>/`) — spawned/forked runs nest under their
  calling session; host-driven runs are roots. Events carry the Router's provenance schema
  (`{ routerId, sessionId, parentId, slot, model, seq, ts, kind:
  "session"|"prompt"|"response"|"toolCall"|"toolOutput"|"fork", … }`) — plus the two
  lineage pointers that make the tree navigable both ways (§8.4): every child-creating
  entry (a delegation's `toolOutput`, a `fork` event) carries `child`, and a forked
  session's opening event carries `forkedFrom(parentId, seq)`; the agents package **adds
  only metadata** — the agent `name` stamped on the session's opening event — so "which
  agent was this" is answerable from the record. Merged `**/transcript.jsonl` ordering,
  `.jsonl`/`.inMemory`/`.none` sinks, redaction levels: all inherited from the Router, none
  re-implemented.
- **Diagnostics are data:** the registry exposes `[AgentDiagnostic]` (duplicate names,
  invalid frontmatter, unsupported fields, unknown tools/skills, unmappable models) so a
  host can render a doctor view; nothing valid is blocked by something invalid next to it.

## 10. Cross-repo prerequisites

This plan **supersedes** two assumptions in the sibling plans, and adds two plain
dependencies (items 3–4):

1. **FoundationModelsSkills** — a **formal, two-part dependency**. (a) Its decision #17 /
   milestone M7 originally placed the future `AgentRegistry` *inside* the Skills target; it
   now lives **here** instead, and the Skills plan has been updated to match (its decisions
   #17 and #19, and M1): Skills exports `FrontmatterDocument` and `FolderStack` as public
   API, and `FolderStack`'s `EntryKind` supports **file-shaped entries** (flat `*.md`,
   recursive scan) alongside directory-shaped ones (`name/SKILL.md`). (b) The `skills:`
   preload capacity (§5) consumes `SkillsRegistry` — Skills' Layer 3 — directly.
   Sequencing: our M1 needs Skills M1; our M2 needs Skills M1–M2; our M6's preload needs
   Skills M3 (`SkillsRegistry`). (c) Skills' search path now rides
   `../FoundationModelsMetadataRegistry` (Skills decision #26), and Skills ships as a
   single target (its #17) — so depending on Skills **transitively carries
   MetadataRegistry and the Router**. Accepted, not a problem: we already require the
   Router directly (item 2 below, §2), the platform floors match (macOS 27+), and no
   lightweight split of Skills' layers is planned or wanted.
2. **FoundationModelsRouter** — the biggest supersession: agent runs are **routed
   sessions**, so the Router grows three things. (a) **Tool-capable sessions** —
   `makeSession(tools:instructions:…)` runs the FM interop tool loop (`MLXLanguageModel`)
   *inside* the recorded chokepoint, emitting the `toolCall`/`toolOutput` events its
   transcript schema already defines. (b) **`spawn`** — a child-session primitive beside
   `fork()`: lineage (`parentId`, nested recording directory) with a *fresh* cache and its
   own instructions/tools, for fresh-context agents. (c) **Per-session observable
   transcripts + the lineage index** — each session exposes an `@Observable`, append-only
   `Transcript` built at the recorder chokepoint (the FM-native
   `LanguageModelSession.transcript` idiom), and lineage makes the set a navigable tree,
   feeding §8.3/§8.4. (d) **Turn delivery** — enqueue a runner-initiated prompt on a
   session *by id* (the §8.5 notification turn), preserving never-vended sessions. Its
   plan's "interop
   available but not load-bearing" is superseded: the interop is load-bearing and lives
   *inside* `RoutedSession`. *(Risk: session-owned KV vs an FM-driven tool loop — §7.)*
3. **[`../FoundationModelsOperationTool`](../FoundationModelsOperationTool/plan.md)** —
   no supersession, just a dependency: `AgentsTool` is one fused `OperationTool` named
   `agents` (§8) — `@Generable @Operation` structs per op, `op: "verb noun"` dispatch,
   the forgiving resolver, and the dual-use CLI for free — so nothing op-shaped is
   hand-rolled here (the Shelltool rule).
4. **[`../FoundationModelsRanker`](../FoundationModelsRanker/plan.md)** — the retrieval
   primitives behind `search agents` (§8): BM25 + trigram + RRF over each listing's
   `name` (primary field) + `description` (body) — the Ranker's two-field weighting
   as-is; cosine is an opt-in that rides the profile's embedder. The index is in-memory
   and rebuilds from the registry's reload publication (§15). *(Supersedes the
   `MetadataSearcher<AgentListing>` reservation this plan previously pointed at
   FoundationModelsMetadataRegistry — retire the mirror note in that plan when it is
   next touched.)*

Packaging: **single SwiftPM library target `FoundationModelsAgents`**, depending on
`FoundationModelsRouter`, `FoundationModelsSkills`, `FoundationModelsOperations`, and
`FoundationModelsRanker` (all as local/sibling packages during development); `./Examples`
executables are additional targets in the same package (§13).
macOS 27+, Swift 6.1 tools, same platform commitment as the Router — no fallback paths.

**Naming note:** the transitive MetadataRegistry dependency (item 1c) exports a public
protocol named **`AgentSession`** (and `RoutedAgentSession`) — its librarian
*selection-session* seam, nothing to do with sub-agents. This package never uses that
name for its own types: a run drives a `RoutedSession`, and the public nouns are
`AgentRun` / `AgentRunner` / `AgentsTool`. Keep it that way, so the overlap stays a
documentation footnote rather than an API ambiguity (the MetadataRegistry plan's §10
carries the mirror note).

## 11. Resolved decisions

1. **FM entry point → one `AgentsTool`** — a fused `OperationTool` named `agents` on
   `FoundationModelsOperations` (the sah op pattern, same as Shelltool; §10), six ops
   sharing one noun: **`list agents` / `search agents` / `start agent` / `check agent` /
   `send agent` / `cancel agent`**. Background-only: there is no foreground run op
   (§8, decision #12).
2. **Identity → frontmatter `name`** (Claude rule; agents are single files), validated
   lowercase+hyphens; full-replace override by name up the stack; duplicate-in-root ⇒
   diagnostic.
3. **Format → Claude-compatible subset**, three tiers: enforced (`name`, `description`,
   `tools`, `disallowedTools`, `model`, `skills`, `maxTurns`), data-only (`color`;
   `background` — every run is background here, `false` draws a diagnostic, §8; unknown
   keys), diagnosed-unsupported (`permissionMode`, `mcpServers`, `hooks`, `memory`,
   `effort`, `isolation`, `initialPrompt`).
4. **Body → literal system prompt.** No argument/shell/Stencil rendering; the dynamic input
   is the task prompt.
5. **Models → slot-mapped**: `standard` / `flash` / `inherit` canonical; Claude aliases map
   (`opus`/`sonnet`/`fable` → standard, `haiku` → flash) via an overridable `ModelMapping`;
   literal model ids draw a diagnostic and fall back to `inherit`.
6. **Execution → tool-capable `RoutedSession`s.** Agent runs are Router sessions — `spawn`
   for fresh-context named agents, `fork` for context-inheriting ones — with the FM tool
   loop (`MLXLanguageModel`) running *inside* the recorded chokepoint. One session system;
   recording, lineage, residency, and the gates are inherited, and `fork` recovers KV
   prefix reuse. *(Supersedes the earlier native-`LanguageModelSession` choice; Router
   growth in §10; KV-vs-FM-loop risk in §7.)*
7. **Tools → host `ToolCatalog`**; omit = inherit all; `disallowedTools` then `tools`
   (Claude order); MCP server patterns (`mcp__…`) honored as prefix matches; unknown
   names diagnosed, with unresolvable *deny* entries escalated (§5). No nested agents
   in v1 (`Agent(...)` entries diagnosed).
8. **`skills:` preload → rendered bodies appended to instructions** at run start, via the
   environment's `SkillsRegistry` — a **formal Skills dependency**, non-optional (an empty
   registry is fine; missing skills are diagnostics). Full content, Claude semantics.
9. **`maxTurns` → counting tool decorator**; crossing the bound cancels the run.
   *(Documented divergence: tool-call count is a strictly-tighter proxy for Claude's
   agentic-turn count, and the stop surfaces as `.failed(hitMaxTurns)` carrying partial
   text — §5.)*
10. **Parallelism → `AgentRunner` actor** with fair FIFO admission (`maxConcurrentAgents`),
    structured cancellation, background runs by id, `@Observable AgentActivity` for UI.
    Per-model serialization acknowledged, not hidden.
11. **Recording → the Router's, unchanged** (§9). A run's transcript is its session's
    `transcript.jsonl` in the Router's lineage tree, nested under its caller; the agents
    package adds only the agent-name stamp on the opening event. No parallel recording
    system.
12. **Background-only delegation — no foreground run op.** `start agent` returns
    immediately; `check agent` (one `id` — or every agent, `id` omitted) is the sole
    harvest point; multitasking is many started
    runs, never a parked tool call — so FM's parallel tool-call behavior is **not
    load-bearing** and its WWDC26 verification item is retired here. *(Supersedes the
    earlier foreground-`run` design; the divergence from Claude's dual style is
    documented in §8.)*
13. **Layer reuse → depend on FoundationModelsSkills** for `FrontmatterDocument` +
    `FolderStack` (with the file-entry generalization) — superseding Skills decision #17's
    same-target `AgentRegistry`.
14. **Packaging → one package**: a single library target plus `./Examples`
    executable/app targets in the same `Package.swift` (§13) — no nested example
    package. macOS 27+ / Swift 6.1, sibling-package dependencies on Router and Skills;
    example-only dependencies join the shared manifest.
15. **Object model → definition ≠ run ≠ session** (§7.1). `AgentDefinition` is data;
    `AgentRun` is the unit of scheduling/cancellation/UI and **drives exactly one
    never-vended routed session** — run id = session id; residency is the session's own
    Router invariant. Runs are **resumable while retained** — `run.send(_:)` / the
    `send agent` op continue the same context; release frees session and context.
16. **Observability → per-profile `AgentActivity`** (`@MainActor @Observable`, §8.1): one
    runner per resolved profile, run snapshots + per-slot **lanes** that visualize the
    serial gates; the `color:` field is consumed here for stable agent badges. Sequential
    profiles ⇒ sequential runners ⇒ one dashboard each.
17. **Calling-transcript events → typed `AgentEvent` tool output** (§8.2). The agent system
    is just a tool, but its result is a *special tool result*: every lifecycle op
    returns a `@Generable AgentEvent` (`started` / `running` / `finished` / `failed` /
    `sent` / `cancelled` / `gone`; the catalog ops `list agents`/`search agents` return
    `[AgentListing]` — the §8 op table) that lands in the calling session's `Transcript` as a structured
    segment — lifecycle first-class in the caller's record, model-visible, UI-renderable.
    Background completions surface at the harvesting `check agent`; live state is
    `AgentActivity`'s job. *(Confirm segment representation against the shipping WWDC26
    SDK.)*
18. **Router enters through the environment; progress is the session's observable
    transcript** (§2, §8.3). The registry is model-free; the Router's single entry point
    is `AgentEnvironment.profile`. Because runs are Router sessions, live progress *is*
    the transcript growing — surfaced as `AgentRun.transcript` (read-only, `@Observable`,
    append-only; the same entries the recorder writes to jsonl), with `AgentActivity`
    adding the scheduler facts no transcript contains. No separate public event stream.
    The §5 decorator remains for `maxTurns` enforcement only.
19. **Tools are context-free → `AgentsTool` is session-bound.** FM's `Tool.call` receives
    only its arguments — no session, no transcript, no caller id, no tool-call id, and no
    mid-call output channel; everything else is captured at construction (Apple's DI
    pattern). So: one `AgentsTool` instance per calling session — the Router's
    `makeSession(tools:)` binds its session id in (giving §7's lineage its mechanism), a
    host-built tool takes an explicit `caller:` (nil ⇒ runs are roots) — and the instance
    is a stateless façade over the runner actor, safe under parallel tool calls. The
    no-mid-call-output constraint is also why §8.4's model/host split is structural, not
    stylistic.
20. **Waiting without blocking → the notification turn** (§8.5). `start agent` ends the turn —
    an instructed contract, not machinery; the runner, via the Router by caller id,
    enqueues one **coalesced** `respond(to:)` on the calling session per batch of
    completions; the session's single-turn discipline serializes it against user turns.
    Policy: `notifications: .automatic` (default) / `.manual` / `.none` on
    `AgentEnvironment`; notification prompts are recorded with `notifying: [sessionIds]`
    provenance; native-`LanguageModelSession` roots are `.manual`. No custom agent loop
    anywhere — the session stays a plain `LanguageModelSession`.
21. **Catalog search → `search agents` on `FoundationModelsRanker`** (§8, §10). When the
    baked-in `name` + `description` surface isn't enough, the model narrows the catalog
    with a ranked query — BM25 + trigram + RRF over `name` (primary) + `description`
    (body); lexical by default, cosine opt-in via the profile's embedder; the in-memory
    index rebuilds from the registry's reload publication (§15). *(Supersedes §1's
    earlier `MetadataSearcher<AgentListing>` reservation on MetadataRegistry.)*

## 12. Public API sketch (illustrative)

```swift
// Layer 3 — stacked, watched, validated definitions. Pure files: NO Router here.
let agents = try AgentRegistry(
  roots: [userAgentsURL, projectAgentsURL],   // low → high; full-replace by name
  watch: true
)
agents.diagnostics                             // [AgentDiagnostic] — doctor view

// Models come from the Router — resolve once, share everywhere (Router plan):
let router  = Router()                         // FoundationModelsRouter
let profile = try await router.resolve(coding, reporting: progress)

// The execution environment — the Router enters HERE, via its resolved profile:
let env = AgentEnvironment(
  profile: profile,                            // Router-resolved LanguageModelProfile
  modelMapping: .default,                      // Claude aliases → slots
  tools: catalog,                              // ToolCatalog: name → Tool factory
  skills: skillsRegistry,                      // SkillsRegistry — `skills:` preload (may be empty)
  notifications: .automatic,                   // completion wakes the caller (§8.5)
  maxConcurrentAgents: 4                       // recordings live with the Router (§9)
)
let runner = AgentRunner(registry: agents, environment: env)

// Host-driven fan-out — root sessions under the Router; no calling session:
let run = try await runner.start("code-reviewer", prompt: "Review:\n\(diff)")
// live in-flight progress (§8.3): run.transcript is @Observable and append-only —
// bind it straight into SwiftUI; its tail entry is the agent card's one-liner (§8.4)
let report = try await run.result()            // final text; run.state observable
let more   = try await run.send("Now check the tests too")   // same session, same context
// Many at once, bounded by admission:
async let a = runner.start("code-reviewer", prompt: p1).result()
async let b = runner.start("test-writer",   prompt: p2).result()

// Layer 4 — model-driven delegation from a root session. AgentsTool is one fused
// OperationTool named "agents" (FoundationModelsOperations, §10) — six ops, one noun:
// list agents / search agents / start agent / check agent / send agent / cancel agent.
let agentsTool = AgentsTool(
  runner: runner,
  caller: nil    // native root session ⇒ model-started runs are Router roots;
)                // router-made sessions bind their own id instead (§7, decision #19)
let root = LanguageModelSession(
  tools: [agentsTool.tool, skillsTool.tool],
  instructions: Instructions { "…base instructions…" }
)
// The root model now sees each agent's name + description and delegates:
// {op: "start agent", name: "code-reviewer", prompt: "Review the diff …"} → started(id)
// at once; the model keeps working, and a later {op: "check agent", id: …} harvests
// the review as a typed finished event.

// Drill in (§8.4) — the join is positional: the delegation entry carries the child id
for entry in root.transcript.entries where entry.child != nil {
  let nested = root.transcript.nested(at: entry)!  // the run's transcript, in place
}

// Per-profile agent observability for SwiftUI (§8.1):
@State var activity = runner.activity          // @MainActor @Observable AgentActivity
// activity.runs → rows; activity.lanes[.standard] → who's generating vs queued
```

Core types: `AgentDefinition` (parsed file), `AgentListing` (metadata view: name,
description, slot, tools, color, provenance), `AgentRegistry`, `AgentEnvironment`,
`ToolCatalog`, `ModelMapping`, `NotificationPolicy` (`.automatic` / `.manual` / `.none` —
§8.5), `AgentsTool` (a fused `OperationTool`, §8) + its `AgentEvent` output (§8.2),
`AgentRunner` (actor; `start(_:prompt:)`; the management index `runs`, `run(id:)` over
every retained run, including model-started ones — §8.4), `AgentRun`
(handle: `id: ULID` — the session id, `agent`, `caller`, `recordURL`, `state`,
`transcript` — a read-only `@Observable`, append-only view of the run's session record
(§8.3), `result()`, `send(_:)`,
`cancel()`), `AgentRunState` (`queued`, `running`, `finished(String)`,
`failed(AgentRunFailure)`, `cancelled`), `AgentRunFailure`, `AgentActivity`
(`@MainActor @Observable`; `AgentRunSnapshot`, `SlotLane`, `AgentColor` — §8.1),
`AgentDiagnostic`.

## 13. Examples — `./Examples`

Runnable examples are part of the deliverable — living documentation and the human-driven
twin of the gated integration suite (§15). `Examples/` holds **executable/app targets in
the root package** — declared in the main `Package.swift`, not a nested package — so one
`swift build` covers library and examples alike; example-only dependencies (e.g.
`swift-argument-parser`) simply join the manifest:

```
Examples/
  agents/                shared agent definitions — a REAL stacked root
    code-reviewer.md       flash slot; tools: Read, Grep
    test-writer.md         standard slot
    summarizer.md          background: true
  DelegateCLI/           model-driven delegation: a root session with AgentsTool —
                         list agents / start agent / check agent — typed AgentEvents in the
                         calling transcript (§8.2 made runnable); ends with a hot-reload
                         beat: edit code-reviewer.md while running, the next run uses
                         the new body (§15's live-reload case, watchable)
  NestedTranscripts/     the §8.4 drill-in walk, minimal — the join is positional:
                         router → root session with a bound AgentsTool → the model
                         starts one agent → walk root.transcript; at the entry whose
                         .child is set, transcript.nested(at:) → print the nested
                         transcript as it grows; fork the conversation — its anchor
                         entry resolves via the same nested(at:); finish at run.recordURL
  FanOut/                host-driven parallelism: runner.start × N across both slots,
                         structured-concurrency await; prints the honesty clause live
                         (same-slot runs queue, cross-slot runs overlap — §8), then
                         walks the Router recording tree it produced (§9)
  AgentDashboard/        SwiftUI app on nested observable transcripts + AgentActivity:
                         one card per run updating in place (the transcript-tail
                         one-liner), color badges, slot lanes, click to drill into the
                         run's live transcript — the §8.4 display contract,
                         demonstrated (§8.1, §8.3)
```

- Each example is small, single-purpose, and reads top-to-bottom as the tutorial for one
  section of this plan — the §12 sketch, made real.
- **`agents/` is a genuine root**, passed to `AgentRegistry(roots:)` — the same files
  exercise discovery, precedence, and diagnostics, and the integration tests may reuse
  them as fixtures.
- **Examples arrive with their milestone, not after it** (§14): `DelegateCLI` and
  `NestedTranscripts` land with M4, `FanOut` and `AgentDashboard` with M5; M7 finishes
  them (README per example, recording-tree walk, doc pass).

## 14. Milestones

- **M1 — Definition parsing + validation.** `AgentDefinition` on `FrontmatterDocument`:
  frontmatter tiers, name validation, tool-list parsing, model mapping (pure). *(Needs
  Skills M1.)*
- **M2 — `AgentRegistry` on `FolderStack`.** Stacked roots, recursive file entries,
  full-replace precedence, duplicate diagnostics, watch/reload — with hot reload as an
  **explicit tested case** (the §15 battery, not a watcher footnote) — `listing()`.
  *(Needs Skills M2 + the file-entry generalization.)*
- **M3 — Execution substrate (the Router growth).** Tool-capable routed sessions, `spawn`,
  per-session observable transcripts + lineage index (§10); one `AgentRun` end to end:
  instructions + resolved tools + slot → spawned routed session → final text. *(The
  heaviest cross-repo milestone.)*
- **M4 — `AgentsTool`.** `list agents` / `start agent` / `check agent` as one fused
  `OperationTool` on `FoundationModelsOperations` (§10); typed
  `AgentEvent` output landing as structured segments in the calling transcript (§8.2);
  live-registry deref with stale-name backstop; background delegation proven from a root
  session (`start agent` → the model keeps working → harvesting `check agent`).
- **M5 — Scheduler + observability.** `AgentRunner` admission gate, `send agent`/
  `cancel agent` and the id-omitted `check agent`, structured cancellation, resumable
  runs (§7.1); the observable
  `run.transcript` surface (§8.3) and `AgentActivity` with run snapshots + slot lanes
  (§8.1).
- **M6 — Semantics fill-in.** `skills:` preload *(needs Skills M3 — `SkillsRegistry`)*,
  `disallowedTools` order, `maxTurns` decorator, model-mapping diagnostics,
  workingDirectory isolation; the `search agents` index *(needs
  `FoundationModelsRanker`)* — BM25 + trigram + RRF over listings, rebuilt on registry
  reload.
- **M7 — Lineage + polish.** Agent-name stamping on session events, delegation-tree
  assertions over the Router recordings tree, diagnostics surface, docs; the `./Examples`
  finish line (§13) — per-example READMEs, recording-tree walk.

## 15. Testing

Unit-testable pieces (frontmatter tiers, identity/precedence, tool-list resolution, model
mapping, maxTurns decorator, scheduler admission/cancellation) take injected definitions and
**stub sessions** — no models, covered per milestone. Registry tests run against fixture
directory stacks; watcher tests against temp dirs.

**Hot reload is an explicit tested case, not a watcher footnote** — the family sets that
bar (MetadataRegistry treats `update(items:)` as a first-class operation with defined
costs; we hold agent definitions to the same standard). The unit battery: add / edit /
remove a definition on disk → the registry rebuilds and `listing()` reflects it; the
`AgentsTool` surface refreshes (the live-registry deref, §7 step 1); an **in-flight run
is untouched** — a run resolves its definition once at start, and no reload mutates it;
a removed agent's next invocation draws the stale-name backstop carrying the refreshed
listing; a rapid burst of edits coalesces to a consistent final state. The registry's
reload publication also feeds the `search agents` index (§8, §10) — same event, second
consumer, no new machinery — and the battery asserts an edited `description` re-ranks
a `search agents` result after reload.

A separate **gated integration suite** (Swift Testing, `.serialized`, opt-in env var —
the Router's pattern, tiny `mlx-community` models) proves: a definition file becomes a live
sub-agent; background delegation round-trips (root → `start agent` → sub-agent tool use →
harvesting `check agent` returns the final text); two concurrent runs on different slots make progress
independently; `check agent`/`cancel agent` behave; a `send agent` follow-up continues a run's context;
`run.transcript` grows with a sub-tool call *while the run is still in flight* (§8.3); the
calling session's transcript carries the run's `started`/`finished` structured segments
(§8.2); a spawned run's `transcript.jsonl` nests under its calling session in the Router
tree, its tool calls appear as recorded `toolCall`/`toolOutput` events, and the merged log
stays totally ordered by `(ts, seq)`; **hot reload end to end** — an on-disk edit to a
definition is picked up live, the *next* delegation of that name uses the updated body and
tools while a mid-flight run of the old definition completes unaffected (§3's live-reload
parity, proven against a real session); **the drill-in walk** (§8.4) — the model starts
an agent from a routed root session, the test finds the delegation entry whose
`entry.child` is set, resolves `transcript.nested(at:)`, observes the nested transcript
grow live, and asserts its entries equal `run.recordURL`'s jsonl; and
**fork nesting** — forking appends a `fork` anchor entry to the parent whose `child`
resolves through the same `transcript.nested(at:)`, the forked transcript holds only
post-fork entries, and its `forkedFrom` marker resolves back to the correct parent entry; and
**the notification weave** (§8.5) — start a slow run, interleave an unrelated user turn,
let the run finish mid-turn, then assert exactly one coalesced notification turn arrives
after the user turn completes, recorded with `notifying: [sessionId]`, and the model's
`check agent` in that turn harvests the result.

---

### Sources
- Claude Code sub-agents — https://code.claude.com/docs/en/sub-agents
- FoundationModelsRouter plan — ../FoundationModelsRouter/plan.md
- FoundationModelsSkills plan — ../FoundationModelsSkills/plan.md
- FoundationModelsOperationTool plan (the `OperationTool` op pattern) — ../FoundationModelsOperationTool/plan.md
- FoundationModelsRanker plan (retrieval primitives behind `search agents`) — ../FoundationModelsRanker/plan.md
- FoundationModelsMetadataRegistry plan (transitive via Skills; our future catalog-search opt-in) — ../FoundationModelsMetadataRegistry/plan.md
- What's new in Foundation Models (WWDC26) — https://developer.apple.com/videos/play/wwdc2026/241/
- Build agentic app experiences with Foundation Models (WWDC26) — https://developer.apple.com/videos/play/wwdc2026/242/
