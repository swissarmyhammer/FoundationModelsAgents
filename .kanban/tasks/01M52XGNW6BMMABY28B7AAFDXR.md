---
assignees:
- claude-code
position_column: todo
position_ordinal: '8680'
title: 'Slash commands: decide if a command run uses SlashCommand.Invocation.workingDirectory as its request folder (D61)'
---
## Why

^47w1swp added a working folder for each run: `AgentRunner.start(_:prompt:workingDirectory:)` and the `workingDirectory` field of `start agent`. The slash-command channel did not change: `AgentRunner.commands(workingDirectory:)` does not use its argument, and the `.action` body calls `start(_:prompt:)`. Thus a `/agent task` run gets the default folder of its agent (the agent folder, or `AgentEnvironment.workingDirectory`), not the folder of the session that ran the command.

## Decision needed

- Option A: the `.action` body gives `invocation.workingDirectory` to `start(_:prompt:workingDirectory:)`. A command run then works in the folder of the session. This changes the current behavior for an agent of the agent-folder source.
- Option B: keep the current behavior, and keep the doc comment that says the argument is not used.

## Acceptance

- A person picks A or B.
- For A: a test of a command run with a session folder, and a test of the doc comment of `commands(workingDirectory:)`.