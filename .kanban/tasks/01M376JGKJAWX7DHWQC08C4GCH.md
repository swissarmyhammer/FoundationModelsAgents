---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3826r3ftdgrafcjway559dy
  text: |-
    Research and implementation notes:
    - `AgentRunner: SlashCommandProviding` is in `Sources/FoundationModelsAgents/Commands/AgentRunner+SlashCommands.swift`. `commands(workingDirectory:)` and `commandUpdates` are nonisolated. They read `registry.catalog()` and `registry.onReload`.
    - The `.action` body starts `runner.start(name, prompt: invocation.arguments)` and waits in `withTaskCancellationHandler`. A cancel of the command stream cancels the run. `AgentRun.result()` waits on the turn task value, and a cancel of the waiter alone does not stop the run, thus the handler is necessary.
    - `commandUpdates` holds a weak reference to the runner through a `@Sendable` closure. A static `relay` function does the loop (review rule: a callback closure that branches calls a named method).
    - New `AgentCatalog.userInvocable`. `AgentReloadReport.init(catalog:marketplaceLayers:)` now computes `slashCommandNames` from `catalog.userInvocable`. The `slashCommandNames:` parameter is removed.
    - Trap: a nested `#require(... #require(...))` does not compile (recursive macro expansion).
    - The fixture `defaults/skills/review/SKILL.md` has no `agent:` key now.
  timestamp: 2026-09-23T21:19:34.511449+00:00
- actor: claude-code
  id: 01m3826ttgmzw92rmykykg7pcc
  text: |-
    ### implement — changed
    - evidence: 7 files — Sources/FoundationModelsAgents/Commands/AgentRunner+SlashCommands.swift, Sources/FoundationModelsAgents/Registry/AgentCatalog.swift, Sources/FoundationModelsAgents/Registry/AgentReloadReport.swift, Examples/agent-library/defaults/skills/review/SKILL.md, Tests/FoundationModelsAgentsTests/SlashCommandTests.swift, Tests/FoundationModelsAgentsTests/FixtureLibraryTests.swift, Tests/FoundationModelsAgentsTests/AgentReloadReportTests.swift. `swift test --filter "SlashCommandTests|FixtureLibraryTests|AgentReloadReportTests"` passes; swiftlint 0.
    - next: test
  timestamp: 2026-09-23T21:19:37.296219+00:00
- actor: claude-code
  id: 01m3827msxmz383ecaeqmdzz6x
  text: |-
    ### test — green
    - evidence: `swift test -Xswiftc -warnings-as-errors` — 260 tests in 35 suites passed, 0 failed, 0 skipped; `swiftlint lint --quiet Sources Tests Examples` 0 violations.
    - next: commit
  timestamp: 2026-09-23T21:20:03.901998+00:00
- actor: claude-code
  id: 01m3827xv9352zq5zjsjkjs67q
  text: |-
    ### commit — changed
    - evidence: a27c046 feat(commands): one slash command for each user-invocable agent
    - next: review HEAD~1..HEAD
  timestamp: 2026-09-23T21:20:13.161492+00:00
- actor: claude-code
  id: 01m382gkavkngykerjwtjw53a8
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` — 0 findings, 0 confirmed, 1 refuted; 6 files reviewed.
    - next: done

    ### finish iteration 1 — clean
    - implement: changed (7 files)
    - test: green (260 tests in 35 suites, swiftlint 0)
    - commit: changed (a27c046)
    - review: clean (0 findings)
  timestamp: 2026-09-23T21:24:57.307324+00:00
depends_on:
- 01M376GQ5AB99BJYWHWW67DVCR
- 01M376XK8GJY5DVQ66492JW7TT
position_column: done
position_ordinal: '9780'
title: 'SlashCommandProviding: one command for each user-invocable agent'
---
## What
Plan.md §9.4 (slash commands). Skills and agents are separate things; this package gives commands for agents only.

- Create `Sources/FoundationModelsAgents/Commands/AgentRunner+SlashCommands.swift`: `AgentRunner` conforms to `SlashCommandProviding`. `commands(workingDirectory:)` gives one command for each user-invocable agent: `name`, `description`, `argumentHint: "<task>"`. The `.action` body starts a host-driven run with the text after the name as the prompt, unchanged, waits, and gives the final text.
- `commandUpdates` yields after each agent `onReload`.
- Fill `AgentReloadReport` slash-command names.
- In `Examples/agent-library/defaults/skills/review/SKILL.md`, remove the `agent: code-reviewer` key, and update `FixtureLibraryTests` to match.

## Acceptance Criteria
- [x] `/code-reviewer check the diff` starts `code-reviewer` with the prompt `check the diff`, and the command gives its final text.
- [x] A `user-invocable: false` agent has no command.
- [x] `commandUpdates` yields after an agent reload, with the new command list.
- [x] `AgentReloadReport` lists the slash-command names.
- [x] No fixture skill has an `agent:` key.

## Tests
- [x] `Tests/FoundationModelsAgentsTests/SlashCommandTests.swift` covers each criterion.
- [x] Run `swift test --filter "SlashCommandTests|FixtureLibraryTests"`, then the full suite. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-09-23 16:20)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 6 file(s) reviewed, 3 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

> 1 file(s) not reviewed — no validator matched:
> - `Examples/agent-library/defaults/skills/review/SKILL.md` — no validator matches this file