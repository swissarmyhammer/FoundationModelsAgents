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
depends_on:
- 01M376GQ5AB99BJYWHWW67DVCR
- 01M376XK8GJY5DVQ66492JW7TT
position_column: doing
position_ordinal: '80'
title: 'SlashCommandProviding: one command for each user-invocable agent'
---
## What
Plan.md §9.4 (slash commands). Skills and agents are separate things; this package gives commands for agents only.

- Create `Sources/FoundationModelsAgents/Commands/AgentRunner+SlashCommands.swift`: `AgentRunner` conforms to `SlashCommandProviding`. `commands(workingDirectory:)` gives one command for each user-invocable agent: `name`, `description`, `argumentHint: "<task>"`. The `.action` body starts a host-driven run with the text after the name as the prompt, unchanged, waits, and gives the final text.
- `commandUpdates` yields after each agent `onReload`.
- Fill `AgentReloadReport` slash-command names.
- In `Examples/agent-library/defaults/skills/review/SKILL.md`, remove the `agent: code-reviewer` key, and update `FixtureLibraryTests` to match.

## Acceptance Criteria
- [ ] `/code-reviewer check the diff` starts `code-reviewer` with the prompt `check the diff`, and the command gives its final text.
- [ ] A `user-invocable: false` agent has no command.
- [ ] `commandUpdates` yields after an agent reload, with the new command list.
- [ ] `AgentReloadReport` lists the slash-command names.
- [ ] No fixture skill has an `agent:` key.

## Tests
- [ ] `Tests/FoundationModelsAgentsTests/SlashCommandTests.swift` covers each criterion.
- [ ] Run `swift test --filter "SlashCommandTests|FixtureLibraryTests"`, then the full suite. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.