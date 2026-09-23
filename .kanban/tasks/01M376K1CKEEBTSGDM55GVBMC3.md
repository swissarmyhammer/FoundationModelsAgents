---
assignees:
- claude-code
depends_on:
- 01M376JMYEG67MVT9NDNATM2AG
- 01M376HQNY14K766HPNACT3999
- 01M376JWWCB68BJF7NGECCBVKH
position_column: todo
position_ordinal: '9780'
title: 'agents-demo: --chat and --fan-out'
---
## What
Plan.md §12, §13, the demo modes that need a resolved profile.

- In `Examples/agents-demo/DemoModes.swift` add two functions that take a `LanguageModelProfile`:
  - `--chat`: a root Router session with the `agents` tool. The `lead` agent starts `code-reviewer` and `test-writer`. The loop prints each `runSettled` event, calls `dispatchNextPrompt()`, and calls `runner.cancelRuns(caller:)` before `close()`.
  - `--fan-out`: two host-driven runs with `async let`, one on each slot, and print both results.
- `main.swift` resolves a real profile for these two modes only.

## Acceptance Criteria
- [ ] The `--chat` function with the scripted profile prints the two child results and the final text of `lead`.
- [ ] The `--chat` function calls `cancelRuns(caller:)` before it closes the root session.
- [ ] The `--fan-out` function with the scripted profile prints two results, one from each slot.

## Tests
- [ ] Add cases to `Tests/FoundationModelsAgentsTests/AgentsDemoTests.swift` that call the two functions with `ScriptedProfile`.
- [ ] Run `swift test --filter AgentsDemoTests`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.