---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3hmtd6h46bma9phtgxhx8tg
  text: |-
    2026-09-27: the Router session planned the per-call mode.
    - Tool hosting (`ToolMounting`, `BackgroundTool`, `ToolContext`, `RunPlane`) moves from the Router to FoundationModelsExtras. Imports in this package change with it.
    - Extras (task id to come): `BackgroundTool.mount(for arguments: GeneratedContent) -> ToolMount`, default `mount`, asked for each call. An operation of an `OperationTool` declares its own mount: `start agent` = background; `list`/`check`/`cancel` = synchronous with no grace wait. A synchronous call returns its real output also when it takes longer than `inlineSettleGrace`; a background call returns a token also when it ends at once.
    - Router task 01M3HMSVSEHS10YD4PZ3RR9RN4: a background run that a synchronous call starts with `ToolContext.mount(... as: .background)` gets its terminal staged one time as mail, so it wakes the pump. It adds session tests for the 4-op case. It depends on Router task 01M3FPCADD0GTFAV2RANXKE7G0 (the Router moves to the Extras tool hosting).
    - The Router session sends the Extras task id and the commits when they are on main. Then remove the tag `waits-on-router` and do this task.
  timestamp: 2026-09-27T14:38:02.961550+00:00
- actor: claude-code
  id: 01m3hmttef7jaacvj7fgjy7cec
  text: |-
    2026-09-27: task ids and the API from the Router session.
    - Extras ^gzhcjp3 (01M3HMSR0XDGD54R903GZHCJP3): a tool chooses background or synchronous for each call.
    - Extras ^2by8wvb (01M3HMSWFHGNG82AS532BY8WVB): each operation declares its mount, and OperationTool chooses it for each call. Depends on ^gzhcjp3.
    - Router 01M3HMSVSEHS10YD4PZ3RR9RN4: stage the terminal of a background run that a synchronous call starts; session tests for the 4-op case. Depends on Router 01M3FPCADD0GTFAV2RANXKE7G0 and on the Extras tasks.
    API (import FoundationModelsExtras):
    - `protocol BackgroundTool { var mount: ToolMount { get }; func mount(for arguments: GeneratedContent) -> ToolMount }`; the default `mount(for:)` returns `mount`; hosting asks `mount(for:)` before each call.
    - `OperationTool`: each operation declares its mount on its definition through `@Operation` (default synchronous). `OperationTool.mount(for:)` reads the op name in the arguments; an unknown name is synchronous. The exact `@Operation` spelling is in ^2by8wvb.
    - `ToolContext.mount(_:op:as: .background)` from inside a synchronous call starts a full background run: a token, tracked, terminal posted as mail.
    Promised: `start agent` returns a token; `list`/`check`/`cancel` answer in-band with no timeout; the start result is mail in every session (host root or run); no `inlineSettleGrace`; whole-tool `mount` users keep working.
    For this task: declare `start agent` as background on its `@Operation`, and keep the other three at the default (synchronous).
  timestamp: 2026-09-27T14:38:16.527673+00:00
- actor: claude-code
  id: 01m3hvcfmyksnxcnrxw7kr7zjb
  text: |-
    2026-09-27: the Extras part is done as LOCAL commits on Extras main. It is not pushed; the user must approve that push. The final API:
    - `BackgroundTool.mount(for arguments: GeneratedContent) -> ToolMount?`; `nil` means "use the host mount". `ToolMounting.call` decides for each call.
    - `@Operation(verb:noun:description:mount:)`; the default is `ToolMount.synchronous`. `OperationTool` is a `BackgroundTool` and uses the mount of the called operation; an unknown operation runs synchronously. `Operations` re-exports `ToolMount`.
    - BREAKING for `Sources/FoundationModelsAgents/Tool/AgentsTool.swift:174`: an `OperationTool` mounted as background now runs EACH call synchronously, unless the operation declares `mount: ToolMount(mode: .background)`. So: declare that mount on `start agent` only, and remove the whole-tool background mount. The Extras CHANGELOG has a migration note.
    - A nested `ToolContext.mount(... as: .background)` posts its terminal to the session sink under its own token. The Router part that stages it as mail is Router task 01M3HMSVSEHS10YD4PZ3RR9RN4, after the Router's current batch.
    Still open before this task can start: the Extras push (user approval) and the Router task.
  timestamp: 2026-09-27T16:32:46.750716+00:00
- actor: claude-code
  id: 01m3j07b1251jzf3qhh6ew4sff
  text: '2026-09-27: Extras is pushed; origin/main is ea9dc99, with the per-call and per-operation mount. Router origin/main is still c208add, and Router task 01M3FPCADD0GTFAV2RANXKE7G0 (the Router uses the Extras tool hosting) is in todo. This package still resolves Extras 0dc42cf. Do not run `swift package update` before 01M3FPCADD0GTFAV2RANXKE7G0 is on Router main: with Extras ea9dc99 and the current code, `start agent` runs synchronously. This task needs only that Router task; it does not need Router task 01M3HMSVSEHS10YD4PZ3RR9RN4, because `start agent` with a declared background mount is a normal background call.'
  timestamp: 2026-09-27T17:57:21.058205+00:00
- actor: claude-code
  id: 01m3mb4g16yhx0yqrx9tfgqgek
  text: |-
    2026-09-28: Router task 01M3HMSVSEHS10YD4PZ3RR9RN4 is done with a clean review; no Router code had to change. With the Router on the Extras tool hosting (Router c93452f and later, Extras 4a733cd), each background run, also a nested `ToolContext.mount(... as: .background)`, sends its terminal through its own funnel to the session outbox, which stages it one time and starts the next submission.
    - Tests of our case: `Tests/FoundationModelsRouterTests/PerCallMountSessionTests.swift` (Router f8168f7): an `OperationTool` with `start agent` declared `mount: ToolMount(mode: .background)`, the other three synchronous; a synchronous call returns its real output also after `inlineSettleGrace`; a background call that ends at once still returns a pending envelope and starts one submission.
    - Example `@Operation` declarations: `Tests/FoundationModelsRouterTests/Helpers/AgentOperationFixtures.swift`.
    - Name clash: a file that imports both `FoundationModelsRouter` and `Operations` sees two `ToolMount` names. Put the `@Operation` declarations in files that import only `Operations` (as the fixture does), or qualify the name.
    - The Router commits are LOCAL on Router main; the push needs the user's approval. Start this task when Router origin/main has c93452f (or later) and f8168f7; then `swift package update` in the root and in `IntegrationTests/` must resolve that Router and Extras 4a733cd or later.
  timestamp: 2026-09-28T15:46:31.078833+00:00
- actor: claude-code
  id: 01m3mcawbvhnhrhd17w23nrnbq
  text: '2026-09-28 correction from the Router session: there is NO `ToolMount` name clash. On Swift 6.4, a file can import both `FoundationModelsRouter` and `Operations` and write `@Operation(..., mount: ToolMount(mode: .background))`, because two typealiases to the same type are accepted. The earlier note about a clash is wrong. Router commit 997bffc (local, not pushed) re-exports the original Extras declarations of `ToolMount`, `ForkableTool`, `OperationEvent`, `OperationEventKind`, `OperationEventSink` and `OperationOutcome`, so a file with only `import FoundationModelsRouter` can use `ToolMount.Mode` in a public declaration. Start condition: Router origin/main has c93452f, f8168f7 and 997bffc (or later).'
  timestamp: 2026-09-28T16:07:28.891269+00:00
- actor: claude-code
  id: 01m3mkp7789ebk1ky5pxaf0cf0
  text: |-
    2026-09-28: the work of ^ggpyaem meets the criteria of this task (not committed yet; this card is not changed).
    - `StartAgent` declares `@Operation(verb: "start", noun: "agent", ..., mount: ToolMount(mode: .background))`. `ListAgents`, `CheckAgent` and `CancelAgent` keep the default synchronous mount.
    - `AgentsTool.mount(for:)` gives `operationTool.mount(for:)`. The whole-tool `mount`, `inlineSettleGrace` and the end-of-submission wait of the start body are removed.
    - Tests: `AgentsToolMountTests` (the mount of each op and of the verb aliases `run`/`status`; list, check and cancel give their real answer in a Router session with no envelope) and `FinalMessageTests.fastChildOfRootSessionComesAsMail` (a host root session gets the final message of a child that ends at once as mail, and the start answer is the pending envelope).
    - Resolved: Router 960dab2, Extras 4a733cd. Unit: 370 tests pass (3 runs). IntegrationTests: 12 tests pass (3 runs).
  timestamp: 2026-09-28T18:16:00.488666+00:00
depends_on:
- 01M3A6EGTPK2A08N066GGPYAEM
position_column: todo
position_ordinal: '9280'
title: 'The agents tool chooses per operation: start agent is background, list/check/cancel are synchronous'
---
## Why
The user decided on 2026-09-27: one `agents` tool, and each operation chooses its own mode. `list agents`, `check agent` and `cancel agent` are synchronous: the call returns only when it has its result. `start agent` returns a background token, and the child's final message comes back as mail. A mode for the whole tool is a mistake that this package does not accept.

BLOCKED outside this board: the Router must let a tool choose background or synchronous for each call. The request went to the FoundationModelsRouter session on 2026-09-27. Remove the tag `waits-on-router` when that Router work is on the Router `main`.

## What
- Use the Router per-call mode in `Tool/AgentsTool.swift`: `start agent` is background; the other three operations are synchronous.
- Remove the whole-tool `.background` mount, the `inlineSettleGrace` constant, and the code that makes `start agent` wait for the end of the caller's submission (`Tool/AgentsToolContext.swift`, `Run/ParentSessionWatch.swift` if nothing else uses it).
- `swift package update` in the root and in `IntegrationTests/`; record the resolved Router revision in a comment.

## Acceptance Criteria
- [ ] `list agents`, `check agent` and `cancel agent` return their result in the tool output, with no pending envelope, however long they take.
- [ ] `start agent` always returns the pending envelope, for a run caller and for a host root caller, and the child's final message always comes as mail.
- [ ] No grace constant and no wait for the caller's submission stay in the agents tool.

## Tests
- [ ] Scripted tests in `Tests/FoundationModelsAgentsTests/AgentsToolOperationsTests.swift` for each operation's mode; a host root and a run caller each get the start result as mail, also when the child ends at once.
- [ ] Run `swift test -Xswiftc -warnings-as-errors` and `cd IntegrationTests && swift test` 3 times. Expected: pass. Report the real results.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.