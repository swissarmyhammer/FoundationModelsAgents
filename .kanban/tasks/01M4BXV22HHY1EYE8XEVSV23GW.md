---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4byc9n6hnw67a6s8vcebeak
  text: |-
    Extras API is final (local main 2c37a78, not pushed yet):
    - `OperationEventKind.message`: the wire value is "message". It is never terminal. `detail` holds the text, and `outcome` is nil.
    - `ToolContext.message(_ text: String) async`: it posts a `.message` event. The event has the tool, the op and the completionToken of the call, the same as `progress(_:)`.
    - After the terminal event of the call, the funnel drops a `.message` and gives no error. A run that is still running always has an open `start agent` call, thus `send caller` from a running child is always delivered.
    - A `.message` resets the timeout window of the run, the same as progress.
    - FoundationModelsAgents has no exhaustive switch over `OperationEventKind` (checked with grep). Thus the update of the package needs no change for the new case.
  timestamp: 2026-10-07T19:45:21.574125+00:00
- actor: claude-code
  id: 01m4c2b32ydp6tgnj86t7hm05m
  text: |-
    Router API is final (Router local main 5713abe, ^v270zf4; it is not pushed yet):
    - `SessionEvent.runMessage(OperationEvent)`.
    - The mail render is `[<tool>] <op> (<token>) message, still running: <detail>`.
    - When only run messages start an answer, the prompt is "Background work you started sent you a message, and it is above. The work is still running, and its result comes later. Act on the message, or say what you did with it." When the mail holds the terminal of a settled run, the settled-run prompt is used.
    - Router aad6ae5 removes `RoutedEmbedder.dimension`. FoundationModelsAgents does not use `RoutedEmbedder`, `PooledEmbedding` or `.dimension` (checked with grep), so this change needs no work here.
    - Update `Package.resolved` and `IntegrationTests/Package.resolved` only after the Router change is pushed to origin.
  timestamp: 2026-10-07T20:54:36.382772+00:00
- actor: claude-code
  id: 01m4c2s0kewamhn4m646kbf84j
  text: 'The Router is on origin/main at 5713abe (aad6ae5 is before it). Extras is on origin/main at 2c37a78. The first step of this task: run `swift package update FoundationModelsRouter FoundationModelsExtras` in the root package and in `IntegrationTests/`. Then build, and confirm that Package.resolved names these SHAs.'
  timestamp: 2026-10-07T21:02:12.590751+00:00
- actor: claude-code
  id: 01m4c6458qmm073hqkwmtmm1c6
  text: |-
    Picked up. Package update done: root and IntegrationTests Package.resolved name Router 5713abe and Extras 2c37a78 (Package.resolved is in .gitignore, so git shows no diff for it).

    Breaking change from the update: `SessionEvent` has four new cases (`compactionStarted`, `compactionFailed`, `reasoningStopped`, `runMessage`). The exhaustive switch in `Examples/agents-demo/DemoModes.swift` `lines(for:)` did not compile. Fix: these four cases give no line. The demo line for `runMessage` is for the CLI task ^m579cf if a line is necessary.

    Research:
    - Tests can not make a `ToolContext` easily (it needs a RunPlane and a sink). A test gets a real one from `AgentStartProbe` (as AgentsToolMountTests does).
    - The scripted model: the `lead` fixture agent has an Agent grant, so a `lead` run that a root session starts has a full tool with a caller link. `.finalTextOfLastPrompt` on the root answers mail with the mail text.
    - Plan: `AgentsToolContext.messageCaller(_:)` and `isCaller(id:)` shared by `SendCaller` and `SendAgent`; `AgentsToolDescription.addingCaller(to:callerID:)` used in both grant branches of `AgentsTool.make`.
  timestamp: 2026-10-07T22:00:43.543147+00:00
- actor: claude-code
  id: 01m4c6pg4qgq1m39cm2efeths3
  text: |-
    Implementation landed.

    - `SendCaller` and the `parent` → `caller` noun alias. `AgentsToolContext.messageCaller(_:)` holds the send logic (no link → "You have no caller.", blank → blankMessage, else `callerLink.call.message`). `SendAgent` calls it when `isCaller(id)` is true (trimmed, case does not matter, compared as ULID). The repeated id normalization in the context is now one `key(of:)` helper.
    - The caller sentence is added in the shared private `AgentsTool.make`, thus both grants get it.

    What did not work first: in `SendCallerTests` the root session and the `lead` run both used the `standard` slot. The child waits on the gate inside its generation call, and it holds the one generation queue of that slot. The root mail answer then waited behind it, and the test hung until the time limit. Fix: the root session is on the `flash` slot. A later test that holds a child on a gate and expects the caller to answer must put the two on different slots.

    Correction of my first comment: the CLI task is ^x3579cf, not ^m579cf. The demo gives no line for `runMessage` now; a line for it belongs to ^x3579cf if one is necessary.

    The build has one build-system warning, "missing creator for mutated node ... mlx-swift_Cmlx.bundle", that was there before any change of this task.

    ### implement — changed
    - evidence: 9 files — Examples/agents-demo/DemoModes.swift, Sources/FoundationModelsAgents/Tool/{AgentsTool,AgentsToolContext,AgentsToolDescription,AgentsToolOperations,AgentsToolText}.swift, Tests/FoundationModelsAgentsTests/{SendCallerTests (new),AgentsToolSchemaTests,AgentsToolDescriptionTests}.swift. `swift test`: 462 tests in 66 suites passed. `swift build --build-tests --package-path IntegrationTests`: complete.
    - next: /review
  timestamp: 2026-10-07T22:10:44.503402+00:00
- actor: claude-code
  id: 01m4c71cwjtv2177rr02f80g3a
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (29ad1d1); 4 findings (4 confirmed, 0 refuted) — Sources/FoundationModelsAgents/Tool/AgentsToolContext.swift:235, Tests/FoundationModelsAgentsTests/SendCallerTests.swift:72, Tests/FoundationModelsAgentsTests/SendCallerTests.swift:80, Tests/FoundationModelsAgentsTests/SendCallerTests.swift:108. No finding is about the grant selection (task ^m6x4er6), thus no finding was dropped.
    - next: implement the 4 open items in the 2026-10-07 17:12 Review Findings section. The task stays in review.
  timestamp: 2026-10-07T22:16:41.618719+00:00
- actor: claude-code
  id: 01m4c71qnptmf287yvg3jeg7x8
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 9 files (packages updated to Router 5713abe, Extras 2c37a78)
    - test: green — swift test, 462 passed in 66 suites (2 runs); IntegrationTests build complete
    - commit: 29ad1d1
    - review: findings — Sources/FoundationModelsAgents/Tool/AgentsToolContext.swift:235, Tests/FoundationModelsAgentsTests/SendCallerTests.swift:72, :80, :108
  timestamp: 2026-10-07T22:16:52.662809+00:00
- actor: claude-code
  id: 01m4c7dv1q6670pj0knzkmm42n
  text: |-
    Review findings (2026-10-07 17:12) done.

    - Finding 1: the new static helper `AgentsToolContext.blankMessageCorrective(_:)` holds the one blank-message check. Both `SendAgent.execute` and `messageCaller(_:)` call it. `messageCaller` keeps its order: no caller first, then blank message.
    - Findings 2-4: the new file `Tests/FoundationModelsAgentsTests/Support/AgentsToolScripting.swift` holds one shared helper of each:
      - `ScriptedAgentStep.agentsToolCall(_:)` (it replaces `toolStep`),
      - `AgentsToolArguments.sendAgent(id:message:)` (it replaces `sendArguments` and `sendAgentArguments`),
      - `AgentsToolHarness.makeRootSession(instructions:slot:adding:)` (it replaces `rootSession`; the default slot is `standard`, SendCallerTests and the defaultSlot test give `\.flash`).
    - The cause was removed in the whole unit test target, not only in SendCallerTests. The private copies in SendAgentTests, AgentSchedulingTests, AgentsToolMountTests, FinalMessageTests and the internal `NestedRunTests.rootSession(of:)` are removed. The inline copies of the same code (`.toolCall(name: ToolVocabulary.agentsToolName, argumentsJSON:)` and `profile.<slot>.makeSession(instructions:, tools: [harness.tool ...])`) in NestedRunTests, NestedRunTests+Limits, MaxTurnsTests, CheckAfterStartTests, CheckAgentProgressTests, AgentRunLoggingTests, AgentSchedulingTests+Setup and AgentSchedulingTests+CallingRun now call the shared helpers.
    - Not changed, on purpose: `.deferredToolCall`, `.repeatedToolCall` and `.toolCallWithLastToken` are different step kinds; root sessions that hold only a probe tool (not `harness.tool`) are a different setup.
    - Each test keeps its slot and its tool list, thus the test behavior is the same.

    Tool note: the `files` `edit file` op with `replace_all: true` replaced only one match per call in this session. Do each edit with a unique context.
  timestamp: 2026-10-07T22:23:29.335453+00:00
- actor: claude-code
  id: 01m4c7dy7f3fpvxfn0tvrj7y8s
  text: |-
    ### implement — changed
    - evidence: 16 files — Sources/FoundationModelsAgents/Tool/{AgentsToolContext,AgentsToolOperations}.swift; Tests/FoundationModelsAgentsTests/Support/AgentsToolScripting.swift (new); Tests/FoundationModelsAgentsTests/{SendCallerTests,SendAgentTests,AgentSchedulingTests,AgentSchedulingTests+Setup,AgentSchedulingTests+CallingRun,AgentsToolMountTests,FinalMessageTests,NestedRunTests,NestedRunTests+Limits,MaxTurnsTests,CheckAfterStartTests,CheckAgentProgressTests,AgentRunLoggingTests}.swift. `swift test`: 462 tests in 66 suites passed. The one build warning "missing creator for mutated node ... mlx-swift_Cmlx.bundle" was there before this task.
    - next: /review
  timestamp: 2026-10-07T22:23:32.591383+00:00
- actor: claude-code
  id: 01m4c7r9natay0td6zvjefwggc
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (91c7cdb); 1 finding (1 confirmed, 6 refuted) — Tests/FoundationModelsAgentsTests/AgentRunLoggingTests.swift:54. All 4 items of the 2026-10-07 17:12 section are checked.
    - next: Do the item in `## Review Findings (2026-10-07 17:25)`. Then run the review again.
  timestamp: 2026-10-07T22:29:11.978777+00:00
- actor: claude-code
  id: 01m4c7rh8dyhwgn81506wvkbfx
  text: |-
    ### finish iteration 2 — findings
    - implement: changed — 16 files
    - test: green — swift test, 462 passed in 66 suites; IntegrationTests build complete
    - commit: 91c7cdb
    - review: findings — Tests/FoundationModelsAgentsTests/AgentRunLoggingTests.swift:54
  timestamp: 2026-10-07T22:29:19.757877+00:00
- actor: claude-code
  id: 01m4c7wxhfa9c2jz87m2309nqd
  text: |-
    Review finding (2026-10-07 17:25) done.

    - `Tests/FoundationModelsAgentsTests/Support/AgentsToolScripting.swift` has two new shared statics: `AgentsToolArguments.listAgents` (the JSON `{"op": "list agents"}`) and `ScriptedAgentStep.listAgents` (the scripted call step of it).
    - The cause was removed in the whole unit test target. A search of `Tests/` for `"op": "list agents"`, `listStep` and `listArguments` found four copies, not three:
      - `AgentRunLoggingTests.listStep`, `CheckAgentProgressTests.listStep`, `MaxTurnsTests.listStep`: deleted; the call sites use `.listAgents`.
      - `MaxTurnsTests.listArguments`: deleted; the `.repeatedToolCall` uses `AgentsToolArguments.listAgents`.
      - `AgentsToolMountTests.listArguments` (the same step, with a different name, through `.agentsToolCall(Self.listArguments)`): deleted; the step is now `.listAgents`.
    - After the change, the only `"op": "list agents"` JSON text in `Tests/` is the shared static. `IntegrationTests/` has no copy.
    - Not changed, on purpose: `harness.call("list agents")` calls the tool directly and is not a scripted step. The `("list agents", .runToCompletion)` mode table and the `DocumentationTests` claim are op names, not a scripted call.
    - The validator rules file was 750k characters. It was not read in full. The change obeys the rules that apply: a doc comment on each new item, no copy of a block, project naming.

    ### implement — changed
    - evidence: 5 files — Tests/FoundationModelsAgentsTests/Support/AgentsToolScripting.swift, Tests/FoundationModelsAgentsTests/{AgentRunLoggingTests,CheckAgentProgressTests,MaxTurnsTests,AgentsToolMountTests}.swift. `swift test`: 462 tests in 66 suites passed. The one build warning "missing creator for mutated node ... mlx-swift_Cmlx.bundle" was there before this task.
    - next: /review
  timestamp: 2026-10-07T22:31:43.407647+00:00
depends_on:
- 01M4BXTKA17C1EXCN9TZ152P5M
position_column: doing
position_ordinal: '80'
title: 'send caller (alias send parent): a run sends a message to its caller as mail'
---
## What
Add the `send caller` operation. `send parent` is a noun synonym of it. A run sends a message to the session that started it, and the run continues. The calling session can be a parent run or the root host session. It gets the message as mail, and the Router starts an answer for it.

Also, `send agent` with an `id` that is the session id of the caller does the same as `send caller`. A run id is the session id, thus the parent run id works as that `id`.

External APIs (the names that the Extras and Router sessions confirmed):
- Extras: `OperationEventKind.message` and `ToolContext.message(_ text: String) async`.
- Router: `SessionEvent.runMessage(OperationEvent)`. An unheld `.message` whose token is an open or a settled background run starts an answer with no caller message (Router kanban `^v270zf4`).

First, update `Package.resolved` and `IntegrationTests/Package.resolved` to the Extras and Router `main` that have these APIs.

Files:
- `Sources/FoundationModelsAgents/Tool/AgentsToolOperations.swift`: new `@Operation(verb: "send", noun: "caller", description: "Send a message to the session that started you. You continue to work. Your final message still goes to it when you end.") struct SendCaller { var message: String }`.
  - `execute` uses `context.callerLink`. With no link, it gives `.corrective(AgentsToolText.noCaller)`: "You have no caller."
  - A blank message gives `.corrective(AgentsToolText.blankMessage)`.
  - Otherwise, it calls `await link.call.message(message)` and gives `.success(AgentsToolText.messageSentToCaller)`.
  - `SendAgent.execute`: before `answer(forRun:)`, if `id` (trimmed, not case-sensitive) is `context.callerLink?.sessionID`, it does the same as `SendCaller`.
- `Sources/FoundationModelsAgents/Tool/AgentsTool.swift`: add `SendCaller` to the full op list and to the `.messagingOnly` op list. Add `nounAliases: ["parent": "caller"]` to the `OperationResolver`.
- `Sources/FoundationModelsAgents/Tool/AgentsToolDescription.swift`: when the context has a caller link, add this sentence: "The session that started you has the id <id>. Send a message to it with {\"op\": \"send caller\", \"message\": \"...\"}."
- `Sources/FoundationModelsAgents/Tool/AgentsToolText.swift`: the texts above.

## Acceptance Criteria
- [x] A running child that calls `send caller` causes a new answer in the parent session. The message text is in the mail of that answer. The child continues, and it ends later with its final message.
- [x] `{"op": "send parent", ...}` resolves to `send caller`.
- [x] `send agent` with the id of the parent run delivers to the parent session.
- [x] A host-started run with a full tool and no caller gets the "You have no caller." corrective.
- [x] The tool description of a run with a caller link names the caller id.

## Tests
- [x] New `Tests/FoundationModelsAgentsTests/SendCallerTests.swift` with the scripted model:
  - the child posts a message;
  - the parent gets a `.runMessage` and answers the mail;
  - then the child finishes and the parent gets the final message.
  - Hold the child with `ScriptedGate` until the parent has answered the message mail, so that this test does not depend on the parent idle rule of the next task.
- [x] Alias test: `send parent` resolves. Parent-id test: `send agent` with the caller id delivers.
- [x] Update `AgentsToolSchemaTests.swift` (both op lists) and `AgentsToolDescriptionTests.swift` (the caller sentence).
- [x] `swift test` passes.

## Workflow
- Use `/tdd`: write the failing tests first, then do the implementation until they pass.

## Review Findings (2026-10-07 17:12)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 9 file(s) reviewed, 4 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

- [x] `Sources/FoundationModelsAgents/Tool/AgentsToolContext.swift:235` `duplication/duplication` — The blank-message guard in messageCaller repeats the guard that SendAgent.execute already runs before it calls messageCaller. The same check and the same corrective are written in two places, so a change to one can drift from the other. Keep one blank-message check for the caller path. Either move the check so that SendAgent calls messageCaller only after its own guard, or add one helper that returns the blank-message corrective or nil, and call it from both SendAgent.execute and messageCaller. Do not change the pre-existing SendAgent guard in place, since it is outside this change; instead remove the new copy from messageCaller or route both through the helper.
- [x] `Tests/FoundationModelsAgentsTests/SendCallerTests.swift:72` `reuse/reuse` — The new `sendAgentArguments` helper builds the same `send agent` JSON as an existing helper in `SendAgentTests`. The two differ only in the id and the message source. Reuse the `SendAgentTests` helper, or move one shared helper into a support file that both suites call. Keep the message as an argument so the `SendCaller` test can pass its own text.
- [x] `Tests/FoundationModelsAgentsTests/SendCallerTests.swift:80` `reuse/reuse` — The new private `toolStep` helper rebuilds a scripted `agents` tool call that already exists as a helper in other test suites. Each copy must be kept in step on its own. Move the shared `toolStep` helper into a test support file (for example beside `ScriptedAgentModel.swift`) and call it from all three suites. Do not add a fourth private copy.
- [x] `Tests/FoundationModelsAgentsTests/SendCallerTests.swift:108` `reuse/reuse` — The new `rootSession(of:)` helper repeats the root-session setup that several other suites already write as their own private helper. This adds one more copy of the same setup. Move the shared root-session helper into a test support file and call it from each suite, or reuse one of the existing helpers if its profile slot and tools match.

## Review Findings (2026-10-07 17:25)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 16 file(s) reviewed, 2 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

- [x] `Tests/FoundationModelsAgentsTests/AgentRunLoggingTests.swift:54` `reuse/reuse` — The constant listStep is defined the same way in three test suites. Each copy wraps the same list agents call. A shared helper is the reuse target, so one definition can be changed once. Add one shared static, for example ScriptedAgentStep.listAgents, in Tests/FoundationModelsAgentsTests/Support/AgentsToolScripting.swift. Use it in all three suites and delete the per-file listStep constants.