---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m37k5h0d1b64jt92w0hs7wgm
  text: |-
    Implementation notes.

    - New: Run/AgentRun.swift (public final class, Mutex state), Run/AgentRunState.swift, Run/AgentRunRequest.swift (internal inputs: definition, prompt, context, inheritedSlot, depth, agentsTool), Run/AgentSessionMaker.swift (plan §8 steps 2-5, typed throws AgentRunFailure). ModelMatch.model(of:in:) gives the RoutedLLM of a slot. AgentBodyRenderer.render is now throws(AgentRunFailure).
    - AgentRunFailure has new cases: agentsMdUnreadable, toolsFailed (setup, no session), contextOverflow (LanguageModelError.contextSizeExceeded), modelFailed (each other turn error). The Router ContextBudgetError is internal, so a hard-ceiling error maps to modelFailed.
    - The turn runs in Task.detached, so it does not take the ToolContext of the calling tool. The text of the turn is the textDelta events after the last textReset.
    - Discovery (plan §16, M3): the Router journals no plain tool invocation record. ToolContext.completionToken reaches transcript.jsonl only through a post through that context (a .toolOutput entry with the OperationEventSegment, correlationID = token, tool = tool name). The lineage test posts .completed through the kept context after the call returns, as M4 will do, and finds that entry.
    - Test support: ScriptedAgentStep.fail(error), AgentRunHarness, AgentStartProbe, RecordedSidecar/RecordedTranscript. AgentRunTests is split in 3 files (Failures and Lineage are nested suites) to keep swiftlint file_length and type_body_length.
  timestamp: 2026-09-23T16:56:45.837954+00:00
- actor: claude-code
  id: 01m37k5kn1m1zt7hmyzrzw3w3d
  text: |-
    ### implement — changed
    - evidence: Sources Run/AgentRun.swift, AgentRunState.swift, AgentRunRequest.swift, AgentSessionMaker.swift, AgentRunFailure.swift, AgentBodyRenderer.swift, ModelMatch.swift; Tests AgentRunTests.swift, AgentRunTests+Failures.swift, AgentRunTests+Lineage.swift, AgentBodyRendererTests.swift, Support/AgentRunHarness.swift, AgentStartProbe.swift, RecordedSession.swift, ScriptedAgentModel.swift. swift test --filter AgentRunTests: 16 tests in 3 suites pass. swiftlint 0.
    - next: test
  timestamp: 2026-09-23T16:56:48.545394+00:00
- actor: claude-code
  id: 01m37k686jnt5hg8e1csh4cw1b
  text: |-
    ### test — green
    - evidence: swift test -Xswiftc -warnings-as-errors — 164 tests in 21 suites pass, 0 failed, 0 skipped; swiftlint lint --quiet Sources Tests Examples — 0 violations
    - next: commit
  timestamp: 2026-09-23T16:57:09.586601+00:00
depends_on:
- 01M376FT1NDWQF9SG4D3XDESSM
- 01M376G12C6R66FY7CM7WBR9XV
- 01M376G689KE03CJKWBS836T5T
position_column: doing
position_ordinal: '80'
title: 'AgentRun: one run drives one RoutedSession end to end'
---
## What
Plan.md §8 steps 1–6 and 8, §8.1, §8.2 (M3). No children, no delivery turns, no `skills:` preload, no `maxTurns` in this task.

- The run id (§8.1): `AgentRun.id` is the session id. `makeSession` makes its own id, so the run does the synchronous steps (resolve, render, instructions, tools, model match, `makeSession`) before `start` returns, and takes `session.id` as its id. Only the turn runs in the background. A run whose render fails has no session: it gets a new `ULID`, no recording directory, and the state `.failed(.bodyRenderFailed)`.
- `Sources/FoundationModelsAgents/Run/AgentRunState.swift`: `public enum AgentRunState { running, finished(String), failed(AgentRunFailure), cancelled }`. Extend `AgentRunFailure` with the context and model errors that a turn can throw.
- `Sources/FoundationModelsAgents/Run/AgentRun.swift`: `public final class AgentRun: Sendable` with `id: ULID`, `agent`, `caller: ULID?`, `depth`, `state`, `recordingDirectory: URL?`, `result() async throws -> String`, `cancel()`.
  1. Keep the resolved `AgentDefinition` for the whole run.
  2. Render the body with the prompt (`AgentBodyRenderer`); a failure fails the run.
  3. Instructions in order: `AgentsMd.documents(from:)` for the working directory (outermost first), then the rendered body.
  4. Resolve the tools (`ToolResolver`).
  5. Match the model; call `model.makeSession(instructions:workingDirectory:tools:budget:compactionPrompt:agentSpawn:)` with `compactionPrompt ?? .default` and `environment.budget(model.contextTokens)`.
  6. In a background task, drive one turn with `session.streamEvents(to: prompt)`. Nothing goes to the caller during the turn.
  8. The text of the last turn is the result. Close the session. A finished run holds no session.
- Lineage: read `ToolContext.current`; `AgentSpawn(parentSessionId: sessionID, parentToolCallId: completionToken)`; `nil` for a host-driven run.

## Acceptance Criteria
- [ ] A scripted run of `code-reviewer` finishes with the scripted final text, on the `flash` slot.
- [ ] `run.id` equals the session id, and `recordingDirectory == <recordingsDir>/<routerId>/<run.id>`.
- [ ] The id is available when `start` returns, before the turn ends (gated turn).
- [ ] A body render failure gives `.failed(.bodyRenderFailed)`, makes no session, has an id, and has no recording directory.
- [ ] The session instructions hold the `AGENTS.md` text first, then the body.
- [ ] The first user prompt of the session is the prompt, with or without `$ARGUMENTS` in the body.
- [ ] The frontmatter `compactionPrompt` reaches `makeSession`; with no key, `.default` reaches it.
- [ ] `environment.budget` gets `model.contextTokens`.
- [ ] `cancel()` during a gated turn gives `.cancelled` and closes the session; a finished run holds no session.
- [ ] A run started inside a tool call of a Router session records `agentSpawn` in its `session.json`, and `parentToolCallId` joins to that tool call in the Router transcript; a host-driven run records none.

## Tests
- [ ] `Tests/FoundationModelsAgentsTests/AgentRunTests.swift` with `ScriptedProfile` covers each criterion.
- [ ] Run `swift test --filter AgentRunTests`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.