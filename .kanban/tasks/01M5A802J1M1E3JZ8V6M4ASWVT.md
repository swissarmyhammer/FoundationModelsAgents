---
assignees:
- claude-code
position_column: todo
position_ordinal: '8280'
title: check agent with the completionToken of a pending call of another tool says that the token is not a run, and that its result arrives as a message
---
## What
SWE-bench run 2026-10-18, django__django-13933 seq 1823: the model called `check agent` with the completionToken of one of its own runCode snippets. The answer was "No run has the id … You have no runs." That is correct, but it doesn't help the model.

When `check agent` (and `cancel agent` / `send agent`, if they share the no-run path, AgentsToolText.swift ~220-235) gets an id that is not a run, look at `ToolContext.current?.backgroundRuns()` (FoundationModelsExtras RunPlane `BackgroundRun`: completionToken, tool, op). When a pending background call of another tool has that token, the answer says so: the id is the completionToken of a pending `<tool>` call (`<op>`), not an agent run; its result arrives as a message, so do not call a tool to wait or check it.

## Tests (failing first)
- AgentsToolOperationsTests: with a pending background run of another tool in the run plane, `check agent` with its token gives the new sentence; an unknown token keeps the current answer.

## Acceptance
- [ ] Tests pass, `swift test` green. #agent-selection