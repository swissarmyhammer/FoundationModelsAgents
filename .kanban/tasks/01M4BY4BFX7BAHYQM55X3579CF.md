---
assignees:
- claude-code
depends_on:
- 01M4BXV22HHY1EYE8XEVSV23GW
position_column: todo
position_ordinal: '8780'
title: CLI and telemetry for send agent and send caller
---
## What
plan.md §9.4 has a parity rule: the CLI mirrors the operations of the tool. Each new operation must also get telemetry that does not record the message text.

Files:
- `Sources/FoundationModelsAgents/CLI/AgentsCLIOperations.swift` and `Sources/FoundationModelsAgents/CLI/AgentsCLI.swift`:
  - Add `agents agent send --id <id> --message <text>`. It calls `send agent` for a run of the host.
  - `send caller` has no CLI command, because a host has no caller. State this in the doc comment.
  - Change "the four operations" in these doc comments to the correct text.
- `Sources/FoundationModelsAgents/Telemetry/AgentsTelemetry.swift`: add a log record and a span event `agent.message.sent` with these attributes:
  - `direction` (`to_run` / `to_caller`);
  - `agent.name`;
  - `run.id`;
  - `outcome` (`delivered` / `ended` / `no_caller`);
  - the message length.
  It does not record the text.
- `Sources/FoundationModelsAgents/Tool/AgentsToolOperations.swift`: call the telemetry in `SendAgent` and `SendCaller`.

## Acceptance Criteria
- [ ] `agents agent send` delivers to a running host-started run, and gives the `runEnded` error for an ended run.
- [ ] Each `send agent` and `send caller` call gives one `agent.message.sent` record with the attributes above.
- [ ] No log record, span attribute or metric label holds the message text.

## Tests
- [ ] Add CLI tests next to the existing `AgentsCLI` tests: delivered and ended.
- [ ] Add a case to `Tests/FoundationModelsAgentsTests/TelemetryContentSafetyTests.swift`: a message with a marker string does not appear in any captured record or span.
- [ ] Add an attribute test to `Tests/FoundationModelsAgentsTests/AgentRunTracingTests.swift`.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd`: write the failing tests first, then do the implementation until they pass.