---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m52x1fckh4wckvm9pydxkhfv
  text: |-
    Research (implement):
    - `AgentSessionMaker.makeSession` uses `environment.workingDirectory` for `SessionConfiguration.workingDirectory` and for `AgentsMd.documents(from:)`. It also makes the `ParentRun` that the `agents` tool of the run gets.
    - `AgentRunRequest` is made in two places: `AgentRunner.start(_:prompt:)` (host) and `StartAgent.execute(in:)` (`start agent`). `ParentRun` carries depth, slot, agent id and family; it has no folder yet.
    - `AgentDefinition.kind.isInAgentFolderSource` is `true` for `.agentFolder` and `.rootDocument`, thus it tells an agent of the agent-folder source from a dotfolder-stack agent. `folderURL` of the default agent is the source root.
    - The Router sidecar (`session.json`) records `workingDirectory` at the top level. A test can decode it next to `configuration.instructions`.
    - `AgentsMd.documents(from:)` walks up to the git root; a temp folder is not in git, thus a test reads only the AGENTS.md of the run folder.
    - Plan: host overload `start(_:prompt:workingDirectory:)`, a `workingDirectory` field on `start agent` (a relative path starts from the folder of the calling run), `AgentRunRequest.requestedDirectory` and one resolve function for the order, `ParentRun.workingDirectory`.
    - Not in scope (card names host API and start agent only): `AgentRunner.commands(workingDirectory:)` / `SlashCommand.Invocation.workingDirectory` still uses the environment folder.
  timestamp: 2026-10-16T17:44:30.355355+00:00
- actor: claude-code
  id: 01m52xh00apd265hvqh1s9kgdw
  text: |-
    Implementation landed (not committed):
    - `AgentRunRequest.requestedDirectory` (the folder of the start request) and `workingDirectory(default:)`: request folder, then `parent?.workingDirectory`, then `definition.folderURL` only when `definition.kind.isInAgentFolderSource`, then `AgentEnvironment.workingDirectory`.
    - `ParentRun.workingDirectory`: `AgentSessionMaker` sets it to the resolved folder of the run, thus each child sees the folder of its parent. The same folder goes to `SessionConfiguration.workingDirectory` and to `AgentsMd.documents(from:)`.
    - Host API: new `AgentRunner.start(_:prompt:workingDirectory: URL?)`. `start(_:prompt:)` stays and calls it with `nil`, thus each DocC link to `start(_:prompt:)` stays valid.
    - `start agent`: new optional field `workingDirectory` (a String). `AgentsToolContext.requestedDirectory(at:)` resolves it: blank text is no folder; a relative path starts from the folder of the calling run (or the environment folder for a session that is not a run); the result is absolute and standardized.
    - Tests: new suite `RunWorkingDirectoryTests` (10 tests). It reads the folder from the Router sidecar (`RecordedSidecar.workingDirectory`, new field) and the `AGENTS.md` note of each folder from the recorded instructions. Paths compare after `resolvingSymlinksInPath()`, because the temp folder is under `/var` -> `/private/var`.
    - Changed existing tests only where a signature or a pinned schema made it necessary: two `ParentRun(...)` calls get `workingDirectory:`, and `AgentsToolSchemaTests` pins the new `workingDirectory?` field.
    - Docs: RunningAnAgent.md (new section "The working folder of a run"), DelegatingWithTheAgentsTool.md, LoadingTheCatalog.md, docs/skills-and-agents.md, and the doc comments of `AgentEnvironment.workingDirectory` and `commands(workingDirectory:)`.
    - Not done by decision (outside the card): tilde expansion of a `start agent` path. Follow-up card ^7aafdxr: should a slash-command run use `SlashCommand.Invocation.workingDirectory`?
  timestamp: 2026-10-16T17:52:58.890563+00:00
- actor: claude-code
  id: 01m52xh45txb6wmxnk9072vnaa
  text: |-
    ### implement — changed
    - evidence: `swift build --build-tests` clean (only the accepted mlx-swift "missing creator for mutated node" line). RED: the new suite did not compile (extra argument `workingDirectory`). GREEN: `swift test --filter "RunWorkingDirectoryTests|AgentsToolSchemaTests"` 20 tests in 2 suites passed. Full suite: `swift test` 567 tests in 79 suites passed, 0 failures. Files: Sources/FoundationModelsAgents/Run/{AgentRunRequest,AgentRun+Children,AgentSessionMaker,AgentRunner,AgentEnvironment}.swift, Sources/FoundationModelsAgents/Tool/{AgentsToolContext,AgentsToolOperations}.swift, Sources/FoundationModelsAgents/Commands/AgentRunner+SlashCommands.swift, docc/{RunningAnAgent,DelegatingWithTheAgentsTool,LoadingTheCatalog}.md, docs/skills-and-agents.md, Tests/.../RunWorkingDirectoryTests.swift (new), Tests/.../{AgentsToolSchemaTests,AgentsToolSelfRuleTests,NestedRunTests+Limits}.swift, Tests/.../Support/RecordedSession.swift
    - next: /review
  timestamp: 2026-10-16T17:53:03.162869+00:00
- actor: claude-code
  id: 01m52xnv6mcdgw4ve5xwt0xre5
  text: |-
    ### test — green
    - evidence: swift test (full suite). 567 tests in 79 suites passed. 0 failures, 0 skipped. 0 compiler warnings.
    - note: only the known SwiftPM line "missing creator for mutated node" for the mlx-swift_Cmlx bundle is in the output. It is accepted.
    - next: review.
  timestamp: 2026-10-16T17:55:37.812135+00:00
- actor: claude-code
  id: 01m52xvhy8fzkn7dzc607c16zq
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (4c216bd): 2 findings, 2 confirmed, 0 refuted — Tests/FoundationModelsAgentsTests/RunWorkingDirectoryTests.swift:141, Tests/FoundationModelsAgentsTests/RunWorkingDirectoryTests.swift:161. Check against the task description: the folder order in `AgentRunRequest.workingDirectory(default:)` is request → parent → agent folder (agent-folder source only) → environment. A relative `start agent` path resolves from the folder of the calling run (`AgentsToolContext.requestedDirectory(at:)`). The code does not expand `~`. Slash-command runs did not change (card ^7aafdxr). The acceptance tests are in RunWorkingDirectoryTests. No more findings.
    - next: move the two test helpers into a shared test support file, then run the review again.
  timestamp: 2026-10-16T17:58:44.936463+00:00
- actor: claude-code
  id: 01m52xw4h72kj8jd5xj7d7710r
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 17 files (8 Sources, 4 docs, 5 Tests incl. new RunWorkingDirectoryTests.swift)
    - test: green — swift test, 567 tests in 79 suites passed, 0 failed, 0 skipped
    - commit: 4c216bd
    - review: findings — Tests/FoundationModelsAgentsTests/RunWorkingDirectoryTests.swift:141, Tests/FoundationModelsAgentsTests/RunWorkingDirectoryTests.swift:161
  timestamp: 2026-10-16T17:59:03.975877+00:00
- actor: claude-code
  id: 01m52y3zjt20vkchhv69tvynv8
  text: |-
    Review findings fixed (not committed):
    - Finding 1 (canonicalPath): new `Tests/FoundationModelsAgentsTests/Support/URL+CanonicalPath.swift` with `URL.canonicalPath` (`standardizedFileURL.resolvingSymlinksInPath().path`). The private `canonicalPath(of:)` of AgentRegistryMarketplaceTests and the private `canonicalPath(_:)` of RunWorkingDirectoryTests are deleted. Both suites now use `url.canonicalPath`. The standardize step does no harm to the marketplace callers.
    - Finding 2 (instructions): new `Tests/FoundationModelsAgentsTests/Support/AgentRunTests+Sidecar.swift`, an extension of `AgentRunTests` that holds `sidecar(of:)` (moved from AgentRunTests.swift, same name, thus no other caller changed) and the new `instructions(of:)`. The private `instructions(of:)` of RunWorkingDirectoryTests is deleted. Each inline `#require(... sidecar(of: run).configuration.instructions)` now calls `AgentRunTests.instructions(of:)`: AgentRunTests, MarketplaceEndToEndTests, ReloadDuringRunTests (2 places), SkillsPreloadTests (its `instructions(ofRunOf:in:)` stays, because it also starts the run and checks the result, but it now calls the shared helper).
    - A search of Tests/ after the change: `configuration.instructions` and `resolvingSymlinksInPath` each occur only in the shared support files (and in the LoadingBoundaryTests rule name, which scans Sources only).
    - Tool note: the `replace_all` option of the files edit op changed only one match in each call. I wrote the whole RunWorkingDirectoryTests.swift file again to change each call site.
  timestamp: 2026-10-16T18:03:21.050298+00:00
- actor: claude-code
  id: 01m52y42x4w9rn8n30zsgwm0be
  text: |-
    ### implement — changed
    - evidence: `swift build --build-tests` clean (only the accepted mlx-swift "missing creator for mutated node" line). Relevant suites: `swift test --filter "RunWorkingDirectoryTests|AgentRegistryMarketplaceTests|SkillsPreloadTests|MarketplaceEndToEndTests|ReloadDuringRunTests|AgentRunTests|NestedRunTests"` 81 tests in 13 suites passed. Full suite: `swift test` 567 tests in 79 suites passed, 0 failures. Both review findings checked. Files: Tests/FoundationModelsAgentsTests/Support/URL+CanonicalPath.swift (new), Tests/FoundationModelsAgentsTests/Support/AgentRunTests+Sidecar.swift (new), Tests/FoundationModelsAgentsTests/{RunWorkingDirectoryTests,AgentRegistryMarketplaceTests,AgentRunTests,MarketplaceEndToEndTests,ReloadDuringRunTests,SkillsPreloadTests}.swift
    - next: /review
  timestamp: 2026-10-16T18:03:24.452986+00:00
- actor: claude-code
  id: 01m52y5rvgaf26zwb0pbj3wrmw
  text: |-
    ### test - green
    - evidence: swift test (full suite) - 567 tests in 79 suites passed, 0 failed, 0 skipped. No compiler warning. The only warning line is the accepted SwiftPM line "missing creator for mutated node" for the mlx-swift_Cmlx bundle.
    - next: review. No commit was made.
  timestamp: 2026-10-16T18:04:19.696217+00:00
- actor: claude-code
  id: 01m52y935qntgkd81aqhtfenyg
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (5c4786c): 0 findings, 0 confirmed, 0 refuted; 8 files reviewed. The 2 prior findings are fixed: Tests/FoundationModelsAgentsTests/Support/URL+CanonicalPath.swift is the one canonicalPath helper (AgentRegistryMarketplaceTests and RunWorkingDirectoryTests use it), and Tests/FoundationModelsAgentsTests/Support/AgentRunTests+Sidecar.swift holds sidecar(of:) and instructions(of:) (SkillsPreloadTests and RunWorkingDirectoryTests use it).
    - next: none. The task is in done.
  timestamp: 2026-10-16T18:06:08.567336+00:00
- actor: claude-code
  id: 01m52y9f1j8p23tm06x31q7yjx
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — 8 test files; the 2 findings fixed and checked
    - test: green — swift test, 567 tests in 79 suites passed, 0 failed, 0 skipped
    - commit: 5c4786c
    - review: clean — 0 findings; the task is in done
  timestamp: 2026-10-16T18:06:20.722820+00:00
depends_on:
- 01M52QK3PC1A6HFXEK7XT42RDF
position_column: done
position_ordinal: e480
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

## Review Findings (2026-10-16 12:56)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 13 file(s) reviewed, 10 not reviewed.

> 6 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 6 file(s)

> 4 file(s) not reviewed — no validator matched:
> - `Sources/FoundationModelsAgents/FoundationModelsAgents.docc/DelegatingWithTheAgentsTool.md` — no validator matches this file
> - `Sources/FoundationModelsAgents/FoundationModelsAgents.docc/LoadingTheCatalog.md` — no validator matches this file
> - `Sources/FoundationModelsAgents/FoundationModelsAgents.docc/RunningAnAgent.md` — no validator matches this file
> - `docs/skills-and-agents.md` — no validator matches this file

- [x] `Tests/FoundationModelsAgentsTests/RunWorkingDirectoryTests.swift:141` `reuse/reuse` — The new `canonicalPath(_:)` helper repeats the `canonicalPath(of:)` helper that already exists as a private static in `AgentRegistryMarketplaceTests`. Both resolve symlinks and return the path. The copies can drift apart, and the existing one is not reachable from this suite because it is private to its own suite. Move one shared path helper into a test support file, such as `Tests/FoundationModelsAgentsTests/Support/`, and have both suites call it. If the `standardizedFileURL` step is needed here, put it in the shared helper, or keep it as a parameter, so both callers use the same logic.
- [x] `Tests/FoundationModelsAgentsTests/RunWorkingDirectoryTests.swift:161` `reuse/reuse` — The new `instructions(of:)` helper repeats the same logic as `SkillsPreloadTests.instructions(ofRunOf:in:)`, which is private to another suite. Both read the recorded sidecar and require a non-nil `configuration.instructions`. The same one-line expression is also written inline in several other test files. This is a weaker finding than the `canonicalPath` one because the helper is a single line, but the duplication is the same kind. Move the sidecar-reading helpers (`instructions(of:)`, and the path helper from the `canonicalPath` finding) into a shared test support file beside `AgentRunTests.sidecar(of:)`, and have the suites call them. If the shared helper is not wanted, at least keep this one a direct call to `AgentRunTests.sidecar(of:)` at the call sites, so the rule lives in one place.
