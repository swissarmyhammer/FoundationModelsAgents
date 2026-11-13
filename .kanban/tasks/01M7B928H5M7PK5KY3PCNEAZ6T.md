---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m7b9k6fw2css8hvp6a72v0ey
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (3633fdd). 5 findings, 5 confirmed, 2 refuted. Sources/FoundationModelsAgents/Registry/AgentConflictVersions.swift:124, Sources/FoundationModelsAgents/Registry/AgentConflictVersions.swift:158, Sources/FoundationModelsAgents/Registry/AgentRegistry+Reload.swift:320 (duplication), Sources/FoundationModelsAgents/Registry/AgentRegistry+Reload.swift:320 (reuse), Tests/FoundationModelsAgentsTests/AgentConflictVersionTests.swift:203.
    - next: Correct each open item in the "Review Findings (2026-11-13 14:27)" section. Then do the review again. The task stays in the review column.
  timestamp: 2026-11-13T20:29:13.084974+00:00
- actor: claude-code
  id: 01m7b9ptfteakdb5jtkbw96kw0
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — AgentConflictVersions.swift, AgentCatalog, AgentRegistry, reload loop, graph types and schema, golden file
    - test: green — swift test, 985 passed
    - commit: 3633fdd
    - review: findings — AgentConflictVersions.swift:124, AgentConflictVersions.swift:158, AgentRegistry+Reload.swift:320 (2), AgentConflictVersionTests.swift:203
    - fix: 9a6fd0d — one startForwardingTask(over:) helper, a plain Sendable presenter, a presenter test that calls each of the three version events, for-in loops. swift test: 986 passed.
  timestamp: 2026-11-13T20:31:11.866681+00:00
- actor: claude-code
  id: 01m7b9r8b9m9wt36ye3qc4afe1
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (commit 9a6fd0d). 3 files reviewed. 7 validator runs, 0 failed. Counts: 0 findings, 0 confirmed, 0 refuted. All 5 items of the prior review section are checked.
    - next: None. The task is in done.
  timestamp: 2026-11-13T20:31:58.825969+00:00
- actor: claude-code
  id: 01m7b9rjd9d15baav84yvar8hs
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — fixes of the 5 findings
    - test: green — swift test, 986 passed
    - commit: 9a6fd0d
    - review: clean — 0 findings, 5 prior findings checked
  timestamp: 2026-11-13T20:32:09.129801+00:00
position_column: done
position_ordinal: ff9d80
title: 'agents endpoint: the iCloud conflict versions of each agent (TestudoApp ^3ysdajb, D154)'
---
## What
The `agents` GraphQL endpoint gives, for each agent, the unresolved iCloud conflict versions of its AGENT.md. The iPad/iPhone client (a pure ACP client) then reads the same data as the Mac app (D154 rule 1). Today the app finds the versions itself with NSFileVersion (D88 (h)).

- New file `Sources/FoundationModelsAgents/Registry/AgentConflictVersions.swift`:
  - `public struct AgentConflictVersion` (`id`, `deviceName`, `modificationDate`).
  - `public protocol AgentConflictVersionSource`: `conflictVersions(of:)` reads the versions of one file. `changes(under:)` gives a value when a version comes or is resolved under a root.
  - `public struct FileVersionConflictSource`: the NSFileVersion source, with an NSFilePresenter on each root for the change signal. The id is the archived `persistentIdentifier` in base64, thus the host resolves it with `NSFileVersion(itemAt:forPersistentIdentifier:)`.
- `AgentRegistry` inits get `conflictVersions:` (default `FileVersionConflictSource()`). Each build reads the versions of the winning file of each agent into `AgentCatalog.conflicts(of:)`.
- `AgentReloadLoop.watch(roots:)` also follows `changes(under:)` of the source, and each value gives a reload. `stopWatching()` stops it.
- Schema: type `AgentConflict { id: ID!, deviceName: String, modifiedAt: DateTime }` and field `Agent.conflicts: [AgentConflict!]!`. A change of the conflicts makes the agent id `changed` in `AgentChange`.

## Acceptance Criteria
- [x] `agents { id conflicts { id deviceName modifiedAt } }` gives the versions of the fake source.
- [x] A new version or a resolve from the source gives one `AgentChange` with the id in `changed`.
- [x] `stopWatching()` stops the follow of the source.

## Tests
- [x] `Tests/FoundationModelsAgentsTests/AgentConflictVersionTests.swift`: a fake source gives a conflict → the endpoint lists it and the subscription sends an event; a resolve → the conflict goes and an event comes.
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #step1

## Review Findings (2026-11-13 14:27)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 10 file(s) reviewed, 3 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

> 1 file(s) not reviewed — no validator matched:
> - `Tests/Fixtures/agents.graphql` — no validator matches this file

- [x] `Sources/FoundationModelsAgents/Registry/AgentConflictVersions.swift:124` `code-hygiene/disallowed-constructs-swift` — no_unchecked_sendable: Instead of @unchecked Sendable, write a plain Sendable conformance or a @preconcurrency import. If the type really must be @unchecked Sendable, write // swiftlint:disable:next no_unchecked_sendable above it with the synchronization invariant that makes the type thread-safe.
- [x] `Sources/FoundationModelsAgents/Registry/AgentConflictVersions.swift:158` `code-hygiene/dead-code-swift` — function.method.instance `presentedSubitem(at:didResolveConflict:)` is unused.
- [x] `Sources/FoundationModelsAgents/Registry/AgentRegistry+Reload.swift:320` `duplication/duplication` — The new conflict-version task in startWatch repeats the body of startUpdatesTask. Both wrap an AsyncStream<Void> in a Task that captures requests and calls requests.yield() for each value. Only the stream variable name differs. If one copy changes, for example to add cancellation handling or a different buffering rule, the other copy can drift out of sync. Add one private static helper, for example `static func startRequestForwarding(over stream: AsyncStream<Void>, to requests: AsyncStream<Void>.Continuation) -> Task<Void, Never>`, that holds the `Task { for await _ in stream { requests.yield() } }` body. Call it from startWatch for conflictTask. Then have startUpdatesTask call it too, or report that call-site change as a separate task so this change stays inside the marked lines.
- [x] `Sources/FoundationModelsAgents/Registry/AgentRegistry+Reload.swift:320` `reuse/reuse` — The new conflict-version task in startWatch(of:conflictVersions:) repeats the body of the existing startUpdatesTask(over:), which already runs `for await _ in stream { requests.yield() }` over an AsyncStream<Void> and returns the Task. The new code duplicates that loop instead of calling the existing helper. Two copies of the same loop can diverge in later fixes, such as cancellation or buffering. Replace the inline Task in startWatch with `let conflictTask = startUpdatesTask(over: changes)`. startWatch is already an instance method, so it can call the helper. Optionally rename startUpdatesTask to a more general name such as startForwardingTask, since it now serves two sources.
- [x] `Tests/FoundationModelsAgentsTests/AgentConflictVersionTests.swift:203` `code-hygiene/idioms-swift` — ReplaceForEachWithForLoop: replace use of '.forEach { ... }' with for-in loop.