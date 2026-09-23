---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m382nzpzcyb4ysc8anmdeq5m
  text: |-
    Research:
    - OperationCLIDriver (Extras OperationsCLI) has no noun alias. The noun of each tree node is the `noun` of the operation. With the model ops, the tree would be `agents agents list` and `agents agent start`.
    - The model `start agent` returns at once. The CLI `start` must wait. Thus the CLI needs its own operations. Decision: four CLI operations in `CLI/AgentsCLIOperations.swift`, each with the noun `agent`: `list agent`, `start agent` (waits, `runner.start(_:prompt:)`, then `run.result()`), `check agent`, `cancel agent`. Check and cancel call the model `CheckAgent`/`CancelAgent`. The tool op `list agents` is not renamed.
    - The driver gives exit code 0 for each value that an operation returns, also a corrective. An error that `execute` throws becomes `OperationError.executionFailed(cause:)`, and the driver gives ArgumentParser's `Error: …` text with exit code 1. Thus a CLI operation throws `AgentsCLIError.corrective(text)` for a corrective, and the exit status is non-zero.
    - The success output is one JSON string (as SkillsCLI). The host decodes it before it writes the text.
  timestamp: 2026-09-23T21:27:53.823161+00:00
- actor: claude-code
  id: 01m382vj6qr6xeez8snb8hx6z4
  text: |-
    ### implement — changed
    - evidence: 8 files — Sources/FoundationModelsAgents/CLI/AgentsCLI.swift (new), CLI/AgentsCLIOperations.swift (new), Tool/AgentsToolContext.swift (startableAgents(matching:)), Tool/AgentsToolOperations.swift (ListAgents uses it), Tool/AgentsToolDescription.swift (Entry.init(_ definition:)), Tool/AgentsTool.swift, Tests/FoundationModelsAgentsTests/AgentsCLITests.swift (new, 10 tests), plan.md §9.4. `swift test --filter "AgentsCLITests|AgentsToolOperationsTests|AgentsToolDescriptionTests"`: 36 tests pass. swiftlint: 0.
    - next: test
  timestamp: 2026-09-23T21:30:56.599319+00:00
- actor: claude-code
  id: 01m382wffygst2z1h058f5wapz
  text: |-
    ### test — green
    - evidence: `swift test -Xswiftc -warnings-as-errors` — 270 tests in 36 suites passed, 0 failed, 0 skipped (NoStandardOutWriteTests included); `swiftlint lint --quiet Sources Tests Examples` — 0 violations.
    - next: commit
  timestamp: 2026-09-23T21:31:26.590663+00:00
- actor: claude-code
  id: 01m38321zwasmv3k1xpd25b5zq
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (18946c6) — 0 findings, 0 confirmed, 2 refuted, 7 files attempted; plan.md and .kanban not matched by a validator.
    - next: done

    ### finish iteration 1 — clean
    - implement: changed — CLI/AgentsCLI.swift, CLI/AgentsCLIOperations.swift, AgentsCLITests.swift (10 tests), Tool/* shared helpers, plan.md §9.4
    - test: green — 270 tests in 36 suites, 0 failed; swiftlint 0
    - commit: changed — 18946c6 feat(cli): AgentsCLI.makeDriver with agents agent list/start/check/cancel
    - review: clean — 0 findings
  timestamp: 2026-09-23T21:34:29.372627+00:00
depends_on:
- 01M376H7W3JTVB6X8M5GBDQNNN
position_column: done
position_ordinal: '9880'
title: AgentsCLI.makeDriver over the four operations
---
## What
Plan.md §9.4 (the CLI). M6.

- Create `Sources/FoundationModelsAgents/CLI/AgentsCLI.swift`: `public enum AgentsCLI` with `public static func makeDriver(runner: AgentRunner) throws -> OperationCLIDriver`, as `../FoundationModelsSkills/Sources/FoundationModelsSkills/CLI/SkillsCLI.swift` does.
- Commands: `agents agent list [--filter <text>]`, `agents agent start --name <name> --prompt <task>`, `agents agent check [--id <id>]`, `agents agent cancel --id <id>`. Each command has the noun `agent`. `OperationCLIDriver` has no noun alias, thus the CLI has its own four operations (`CLI/AgentsCLIOperations.swift`) over the same `AgentsToolContext`. The tool op `list agents` keeps its name.
- CLI `start` waits for the run and prints the final text (no `ToolContext`, thus no post). `check` and `cancel` are for a host process that stays alive.
- The library writes nothing to standard output; the driver gives the text to its caller. A command that works gives one JSON string and exit code 0. A corrective or a failed run gives the reason and a non-zero exit code.

## Acceptance Criteria
- [x] `agent list` gives one `- name: description` line for each model-visible agent.
- [x] `agent start --name code-reviewer --prompt x` gives the scripted final text.
- [x] An unknown name gives the corrective text and a non-zero exit status.
- [x] `NoStandardOutWriteTests` stays green.

## Tests
- [x] `Tests/FoundationModelsAgentsTests/AgentsCLITests.swift` drives the driver with arguments and the scripted profile.
- [x] Run `swift test --filter AgentsCLITests`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.