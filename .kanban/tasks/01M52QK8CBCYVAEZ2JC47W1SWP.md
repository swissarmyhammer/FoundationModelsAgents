---
assignees:
- claude-code
depends_on:
- 01M52QK3PC1A6HFXEK7XT42RDF
position_column: todo
position_ordinal: '8480'
title: A working folder for each run, with the agent folder as the default (D61)
---
## Why

Decision D61 of the SwissArmyHammer app: a session is an agent plus a working folder. Any agent can work in any folder. When the user selects no folder, an agent from the agent-folder source (`agentFolders`, see ^xt42rdf) works in its own folder.

## Problem in the current code

`AgentEnvironment.workingDirectory` is one value for each run of the environment (`AgentEnvironment.swift:82`). `AgentSessionMaker` uses it for the session and for `AgentsMd.documents(from:)` (`AgentSessionMaker.swift:70`, `:93`). A run cannot have its own folder.

## Plan

1. Add an optional working folder to the start of a run (the host API and the `start agent` operation).
2. The order of the value (agreed with the app session, recorded in AG-4 and AG-5):
   1. The folder of the start request.
   2. For a child run: the folder of the parent run.
   3. Only for an agent from the agent-folder source: `AgentDefinition.folderURL`.
   4. `environment.workingDirectory`.
   An agent from the dotfolder stack (marketplace, defaults, user, project `agents/<id>/`) never uses its own folder. Its folder is a definition in a configuration folder.
3. The `AGENTS.md` documents come from the working folder of the run.

Reason for the order: a parent that delegates expects the child to work on the files of the parent, unless the request names a folder. The agent-folder default is for a root run that has no folder. The D60 coordinator starts root runs, not child runs: its tasks use the request folder, or the agent folder when the task names no folder.

## Acceptance

- Tests: a run with its own folder; a root run of an agent-folder agent uses its folder; a root run of a dotfolder agent uses the environment folder; a child run uses the folder of its parent, also when it is an agent-folder agent; a request folder wins over all.
- The current API and tests keep working.

Depends on ^xt42rdf.