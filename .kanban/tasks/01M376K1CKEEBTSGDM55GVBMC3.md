---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m384s84nfb8aze8yvjme23jb
  text: |-
    Research done.
    - The demo target cannot see internal symbols. `AgentRunner.runs(caller:)` is internal. The chat mode needs it to find the runs that the root session started and their children. Plan: make `runs(caller:)` public (it has a doc comment).
    - `runSettled` of a run always goes to `streamSessionEvents()` (the turn sink also forwards to the session feed). Subscribe before the first turn. The chat loop waits for one `runSettled` for each run of the first turn, calls `dispatchNextPrompt()` after each one, then calls `cancelRuns(caller:)`, then `close()`.
    - Real profile: `Router(recordingsDir:, loader: LiveModelLoader(downloader: #hubDownloader(), tokenizerLoader: #huggingFaceTokenizerLoader()))`, then `router.resolve(profile: ProfileDefinition(...), reporting: ResolutionProgress())`. This is the pattern of `../FoundationModelsACPAgent/Sources/acp-agent/AgentComposition.swift`. The macros need the products MLXHuggingFace + MLXLMCommon (mlx-swift-lm, branch stable), HuggingFace (swift-huggingface), and Tokenizers (swift-transformers). Only the demo target links them. The library target does not.
    - Fan-out: code-reviewer is on flash and test-writer is on standard, so the two runs use different generation gates. The test reads the slot of each session from its `session.json`.
  timestamp: 2026-09-23T22:04:37.909892+00:00
- actor: claude-code
  id: 01m385t35eb3hr8ws3aaw1kzbk
  text: |-
    ### implement — changed
    - evidence: 8 files — Examples/agents-demo/DemoModes.swift (chat, fanOut, line helpers), Examples/agents-demo/AgentsDemoMode.swift (--chat, --fan-out, usage), Examples/agents-demo/AgentsDemoMain.swift (withResolvedProfile), Examples/agents-demo/AgentsDemoProfile.swift (new: live Router + ProfileDefinition), Examples/agents-demo/AgentsDemoLibrary.swift (projectDirectory), Package.swift (live loader products for the demo target only), Sources/FoundationModelsAgents/Run/AgentRunner.swift (runs(caller:) is public), Tests/FoundationModelsAgentsTests/AgentsDemoTests.swift (3 new cases + 2 flag checks).
    - `swift build --build-tests -Xswiftc -warnings-as-errors`: clean. `swift test --filter AgentsDemo`: 8 tests in 2 suites pass. swiftlint: 0. periphery: no new result (the 6 `AgentDefinitionRules` unused-parameter results were there before).
    - Notes: `RoutedSession.streamSessionEvents()` is actor-isolated, so call it with `await`. The chat test proves `cancelRuns(caller:)`: the root starts a gated code-reviewer (flash) in its delivery turn, and the run tree after close shows it as `cancelled`.
    - next: test
  timestamp: 2026-09-23T22:22:34.158913+00:00
- actor: claude-code
  id: 01m3860wrtvcjrdz0bn40fjgjr
  text: |-
    ### test — green
    - evidence: `swift test -Xswiftc -warnings-as-errors` — 278 tests in 38 suites passed, 0 failed, 0 skipped; `swiftlint lint --quiet Sources Tests Examples` — 0 violations. The mlx-swift "missing creator" build note is not ours.
    - next: commit
  timestamp: 2026-09-23T22:26:16.986015+00:00
- actor: claude-code
  id: 01m3861bdb86fx9kcn7c396ztf
  text: |-
    ### commit — changed
    - evidence: de71dc9 feat(demo): agents-demo --chat and --fan-out over a resolved profile
    - next: review HEAD~1..HEAD
  timestamp: 2026-09-23T22:26:31.979610+00:00
- actor: claude-code
  id: 01m386jptdx1e9bv0r4be1msws
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD — 1 finding (1 confirmed, 0 refuted): Tests/FoundationModelsAgentsTests/AgentsDemoTests.swift:358 completeness/public-output-contract
    - next: implement (move `@escaping` outside the parentheses of `lines(of:)`)

    ### finish iteration 1 — findings
    - implement: changed (8 files)
    - test: green (278 tests, 38 suites)
    - commit: de71dc9
    - review: findings (1) — AgentsDemoTests.swift:358
  timestamp: 2026-09-23T22:36:00.717727+00:00
depends_on:
- 01M376JMYEG67MVT9NDNATM2AG
- 01M376HQNY14K766HPNACT3999
- 01M376JWWCB68BJF7NGECCBVKH
position_column: doing
position_ordinal: '80'
title: 'agents-demo: --chat and --fan-out'
---
## What
Plan.md §12, §13, the demo modes that need a resolved profile.

- In `Examples/agents-demo/DemoModes.swift` add two functions that take a `LanguageModelProfile`:
  - `--chat`: a root Router session with the `agents` tool. The `lead` agent starts `code-reviewer` and `test-writer`. The loop prints each `runSettled` event, calls `dispatchNextPrompt()`, and calls `runner.cancelRuns(caller:)` before `close()`.
  - `--fan-out`: two host-driven runs with `async let`, one on each slot, and print both results.
- `main.swift` resolves a real profile for these two modes only.

## Acceptance Criteria
- [x] The `--chat` function with the scripted profile prints the two child results and the final text of `lead`.
- [x] The `--chat` function calls `cancelRuns(caller:)` before it closes the root session.
- [x] The `--fan-out` function with the scripted profile prints two results, one from each slot.

## Tests
- [x] Add cases to `Tests/FoundationModelsAgentsTests/AgentsDemoTests.swift` that call the two functions with `ScriptedProfile`.
- [x] Run `swift test --filter AgentsDemoTests`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-09-23 17:26)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 8 file(s) reviewed, 2 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

- [ ] `Tests/FoundationModelsAgentsTests/AgentsDemoTests.swift:358` `completeness/public-output-contract` — Function parameter type has incorrect syntax — `@escaping` attribute is incorrectly nested inside parentheses, which changes the meaning of the type signature. The signature declares an input parameter of type `@escaping AgentsDemoOutput`, which is invalid; it should declare the parameter as an escaping function that takes an `AgentsDemoOutput` and returns async-throwing-Void. Change line 358 from `of body: (@escaping AgentsDemoOutput) async throws -> Void` to `of body: @escaping (AgentsDemoOutput) async throws -> Void` — move the `@escaping` attribute outside the parentheses so it applies to the entire function type.