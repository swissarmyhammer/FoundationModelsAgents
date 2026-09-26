---
assignees:
- claude-code
depends_on:
- 01M3A6EGTPK2A08N066GGPYAEM
position_column: todo
position_ordinal: '9080'
title: 'Hosts on the Router pump: agents-demo, slash commands, the CLI and the README example'
---
## What
After ^ggpyaem, the Router pump delivers messages and settled runs. A host sends with `send(_:)` or `respond(to:)` and does not drive a loop.
- `Examples/agents-demo/DemoModes.swift`: remove the driver loop (`chat`, `converse`, `deliverSettledRuns`). `--chat` sends each user line with `send(_:)` and prints the answers from `streamSessionEvents()` (`answered`, `textDelta`), including the answers that mail starts. `--fan-out` shows the same flow for several children.
- `Commands/AgentRunner+SlashCommands.swift` and `CLI/AgentsCLIOperations.swift`: keep `start` + `result()`, and check that they need no driver call. Correct the doc comments.
- The README example (`README.md` and `Tests/FoundationModelsAgentsTests/ReadmeExampleSource.swift`): a root session with the `agents` tool uses `respond(to:)` and then gets the child's result as mail with no host loop.
- `mailDeliveryPaused` at a host: the demo prints it and tells the user to send a message.

## Acceptance Criteria
- [ ] No host code calls a driver method or waits in a loop for settled runs.
- [ ] The demo `--chat` shows the answer that the child's mail starts, with no user input.
- [ ] `ReadmeExampleTests` runs the example with the scripted model and sees the parent's answer to the child's mail.

## Tests
- [ ] Update `AgentsDemoTests.swift`, `ReadmeExampleTests.swift`, `ReadmeExampleSource.swift`, `AgentsCLITests.swift`, and the slash command tests.
- [ ] Run `swift test -Xswiftc -warnings-as-errors`. Expected: pass.
- [ ] Run `cd IntegrationTests && swift test`. Expected: pass. Report the real results.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.