---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3fm42jsye447n4a84hvk09d
  text: |-
    ### Research: resolved revisions and the new Router API

    `swift package update` ran at the root and in `IntegrationTests/`. Both resolve the same revisions:
    - FoundationModelsRouter main c208add725b8c0f1bc784f162b437138ff8b0561. It holds ^44y6ba4 (79fe2cb, 50a629e), ^93kjn94, ^8csj2hw and ^f33q8gw.
    - mlx-swift-lm stable a1f77ad9337bc6dbbcf515f6c0f51199add3da8f
    - FoundationModelsExtras main 0dc42cfd6b434af36d82281d2772b1c3a7882566
    - FoundationModelsSkills main ed142ece8bab35a2ce7500133627beea9fa4267e

    The build (`swift build --build-tests -Xswiftc -warnings-as-errors`) fails:
    - `Sources/FoundationModelsAgents/Run/AgentRun+TurnLimit.swift`: error: value of type 'any RoutedSession' has no member 'dispatchNextPrompt'
    - `Sources/FoundationModelsAgents/Run/AgentRun+TurnLimit.swift`: error: value of type 'any RoutedSession' has no member 'cancelCurrentTurn'
    - The same removed API is also in `AgentRun+Children.swift` (`enqueue(prompt:)`), `Examples/agents-demo/DemoModes.swift`, `IntegrationTests/.../FullCircleTests.swift`, `Tests/.../NestedRunTests.swift`, `Tests/.../ReadmeExampleSource.swift`, README.md, DocC `TheFinalMessage.md`, `DocumentationTests.swift` and plan.md §8 steps 7 and 8.

    What the Router changed (Router `generation-queue.md` section 5, `RoutedSession.swift`):
    - The item of the model queue is one whole submission (one SDK call, with its passes AND its tool bodies), not one pass. The user chose this on 2026-09-25 (section 5.1). This replaced the per-pass design of ^8csj2hw that this task was written for.
    - `dispatchNextPrompt()`, `enqueue(prompt:)`, `PromptID` and `cancelCurrentTurn()` are gone. The replacements are `send(_:)`, `MessageID`, `cancel()` and `cancel(message:)`. A session has a pump that delivers mail with no caller call.
    - The pump starts a submission for mail only when the mail is the terminal of a TRACKED background run (`SessionOutbox.canStartASubmission`, `SessionMailbox.settledRunTokens()`; only `BackgroundToolRunner` calls `SessionMailbox.track`). The `agents` tool is an in-band tool. Thus the final message of a child run stays staged until the next caller message.
    - Section 5.10 names the change for this package: "Remove the external driver (the pump delivers messages and settled runs); `cancel()`; the agent tool must start a child as a background run and return at once." The Router task for the consumers (^d7d777f) was deleted: "the user updates the consumers separately".
    - The unit-test backend `ScriptedSessionBackend` has no executor seam and names no `generationQueue`, thus the unit tests now run with no model queue at all.
  timestamp: 2026-09-26T19:47:22.329773+00:00
- actor: claude-code
  id: 01m3fm4b4jfa4hh7p6eggagv1v
  text: |-
    ### Blocker: the card conflicts with the Router design that shipped

    1. **Acceptance criterion 3 and the new NestedRunTests case conflict with the Router contract.** The card says: "A parent and a child on the same model both make progress while the parent waits in a tool." The card was written for the per-pass queue of ^8csj2hw. The Router that shipped makes one whole submission the item (`generation-queue.md` 5.1). `RoutedSession` states: "a tool body, or a wait for a person inside it, holds the model for every other session on it." Section 5.5 states: "A tool body that waits for an answer of a session on the same model can never end." Thus on a real model the child cannot generate while the parent waits in an in-band tool. The criterion is possible only with a background tool (the parent's submission ends, and the child's result comes back as mail). A unit test with the current scripted backend would pass only because that backend has no queue (`LanguageModelSessionBackend.generationQueue` is nil), so it would prove a false claim.
    2. **The replacement for `dispatchNextPrompt()` is a design decision that the card does not make.** The run loop of plan.md §8 steps 7 and 8, the README example, DocC `TheFinalMessage.md`, `agents-demo --chat`, and `FullCircleTests` all call `dispatchNextPrompt()`. There are two ways:
       - A: keep the in-band `agents` tool. The run (and a host) sends its own delivery message (`respond(to:)` or `send(_:)`), and the staged posts go in as the preamble. The run must count the child endings itself, because no call now gives `nil` for "nothing staged". The public docs change from `dispatchNextPrompt()` to a sent message.
       - B: the Router's own advice (section 5.10): make `start agent` a background run, so the pump delivers each final message with no driver. This changes the tool output (a `PendingRunEnvelope`), the four-operation tool shape, and the host contract.

    No file in the repository changed. Only the git-ignored `Package.resolved` files changed.

    A person must choose A or B and restate acceptance criterion 3 and the NestedRunTests case, for example as "the parent waits in a background tool", or remove them.
  timestamp: 2026-09-26T19:47:31.090524+00:00
- actor: claude-code
  id: 01m3fm4gx5atfdscxjgctg52gr
  text: |-
    ### implement — stuck
    - evidence: Router c208add (holds ^44y6ba4), mlx-swift-lm a1f77ad, FoundationModelsExtras 0dc42cf, FoundationModelsSkills ed142ec; the root and IntegrationTests/ resolve the same revisions. The build fails: "value of type 'any RoutedSession' has no member 'dispatchNextPrompt'" and "... no member 'cancelCurrentTurn'" in Sources/FoundationModelsAgents/Run/AgentRun+TurnLimit.swift. The Router symbols `RoutedSession.dispatchNextPrompt()`, `RoutedSession.enqueue(prompt:)` and `RoutedSession.cancelCurrentTurn()` are removed. The replacement is `send(_:)` / `cancel()` and the session pump. Acceptance criterion 3 conflicts with the Router contract (a submission holds the model through its tool bodies). No repository file changed. No unit or live test ran, because the package does not compile.
    - next: a person chooses design A (the run sends its own delivery message) or design B (a background `start agent`), and restates or removes criterion 3 and its NestedRunTests case. Then run /implement again.
  timestamp: 2026-09-26T19:47:36.997726+00:00
- actor: claude-code
  id: 01m3fm5k5q0ebjzcf6vhyq6t5q
  text: |-
    ### finish iteration 1 — stuck (design decision)
    - implement: stuck — the package does not compile with Router c208add. `RoutedSession.dispatchNextPrompt()`, `enqueue(prompt:)`, `PromptID` and `cancelCurrentTurn()` are removed. The new API is `send(_:)`, `cancel()`, `cancel(message:)`, and a per-session pump that delivers mail.
    - The shipped Router queues one whole SDK call (tool bodies included), not one pass (`generation-queue.md` §5.1, §5.5, §5.7). An in-band tool that waits holds the model, and the Router refuses a same-model wait from inside a submission. Long work must be a background tool (§5.5 rule 1), and its result comes back as mail.
    - Acceptance criterion 3 ("a parent and a child on the same model both make progress while the parent waits in a tool") is not true for an in-band tool with this Router.
    - A person must choose: (A) keep the in-band `agents` tool, and the run sends its own delivery messages with `send(_:)`; or (B) make `start agent` a background tool, so the pump delivers each final message as mail (Router §5.10).
    - Resolved (gitignored Package.resolved, root and IntegrationTests): Router c208add, mlx-swift-lm a1f77ad, FoundationModelsExtras 0dc42cf, FoundationModelsSkills ed142ec. With these, the package does not build, so every other task is blocked until this task is done or the resolved files go back.
  timestamp: 2026-09-26T19:48:12.087637+00:00
- actor: claude-code
  id: 01m3fnh48y6n3wpj6a9krf3gqx
  text: |-
    ### Research for the background design (picked up again after the rewrite)

    Router facts that the design uses (read at c208add):
    - `BackgroundToolRunner.launch` posts one progress event (the envelope), tracks the run, starts the body, then waits `inlineSettleGrace`. A body that settles inside the grace answers in the same envelope (`pending` false), and its staged events are withdrawn. The grace wait is inside the submission of the caller, so that submission cannot end before the envelope goes back.
    - The body runs with `ToolContext.current` bound; its `completionToken` is the run token and the `correlationID` of the terminal.
    - A supplied `canceler(forCompletionToken:)` of a `.swiftTask` run replaces the cooperative one; the Router then does not cancel the body task. `SessionMailbox.sweep()` calls the canceler and does not wait for the body.
    - `SessionOutbox.post` stages the terminal BEFORE the journal write that emits `runSettled`. A submission that takes mail for another reason (another settled run, a caller message, a continuation) can thus take a terminal before its `runSettled` is emitted. So "runSettled, then submissionStarted" alone can wait for ever for a second child. The run therefore checks delivery in the settled transcript: the child's final message text is in a `.prompt` entry.
    - `answerFailed.reason` is only a string. To keep `contextOverflow` for the task answer, the task prompt goes in as one message with `streamEvents(to:)` (a send plus a wait for its own answer), which throws the typed error. Mail answers fail with `answerFailed` and an empty `messageIds`.
    - `generationCall` comes one time for each pass when the backend reports usage (the first tool open of a pass, and the submission close). `entryRecorded` comes at the end of each submission.
    - `GenerationQueue` is public with a public init, and `LanguageModelSessionBackend.generationQueue` can name one. The scripted container can own one queue for each model, so runs on one model share its queue in the unit tests.

    Design decisions:
    - A child that settles inside the grace would give its result inline, and no mail. To keep "start agent returns at once with the pending envelope", the start body of a run parent waits, after the child ends, for the end of the parent's submission that made the call. The parent's event follower opens this gate at the first `submissionEnded` after the open `toolInvocation` record of the call. A host root session has no follower, so a fast child there can still settle inline.
    - `check agent` and `cancel agent` also accept the completion token of the start call, because the pending envelope carries the token and not the run id.
  timestamp: 2026-09-26T20:11:58.622779+00:00
- actor: claude-code
  id: 01m3frvkkvsha86e9w6b3zrvjy
  text: 'Progress: The unit suite passes (367 tests, 50 suites, 2 runs in a row). swiftlint has 0 violations. swift build -Xswiftc -warnings-as-errors passes, and agents-demo builds. periphery shows no new item (I removed the unused AgentRun.parent). The IntegrationTests package compiles: LiveAgentsToolProbe now conforms to BackgroundTool and gives each part to the real tool. FullCircleTests and LiveNestedTests wait for the mail answer of the root. They read only the `.completed` posts, and they find the start answer by the completion token. Live run 1: 12 tests in 6 suites passed.'
  timestamp: 2026-09-26T21:10:07.739456+00:00
- actor: claude-code
  id: 01m3frybhn974b4rk1jbaxh9r4
  text: |-
    step: implement
    outcome: changed
    evidence: swift build -Xswiftc -warnings-as-errors passes in the root and in IntegrationTests. swift test -Xswiftc -warnings-as-errors: 367 tests in 50 suites passed, 3 runs in a row. agents-demo builds. swiftlint: 0 violations (Sources, Tests, Package.swift, Examples, and the 4 changed IntegrationTests files). periphery: no new item. cd IntegrationTests && swift test, 3 runs: 12 tests in 6 suites passed each time (122.5 s, 170.4 s, 129.9 s). The criterion "start agent returns at once with the pending envelope" is not checked. For a run parent it is true: the start body waits until the submission of the parent ends. For a host root session, a child on another model that ends inside the 1 s inlineSettleGrace settles in the start envelope, not as mail. The tool cannot see when a host root submission ends. Task ^0mhzx3a (hosts) must decide this. Each start answer gives outcome `.succeeded`, and the detail tells the state (finished, failed or cancelled). For ^7f7z6qa: TheFinalMessage.md and plan.md still name dispatchNextPrompt(), and a DocumentationTests claim checks that text. The README usage block and the dispatchNextPrompt paragraph got the smallest change, and ReadmeExampleSource.swift matches the README. AgentSchedulingTests still puts two gated runs on two models, because two held runs at one time need two generation queues. Not committed, not pushed.
    task: ^ggpyaem
  timestamp: 2026-09-26T21:11:37.781672+00:00
depends_on:
- 01M3A6DQW7S7GYSPTDY3QHG0XH
- 01M3A6DZBWW4SMKGJCA3H1KBYF
position_column: doing
position_ordinal: '80'
title: 'Runs on the Router pump: start agent is a background run, and a run ends when its session is idle'
---
## Why
The Router at `c208add` (resolved in both packages; see the comments) queues one whole SDK call, tool bodies included, and delivers mail with its own per-session pump. `dispatchNextPrompt()`, `enqueue(prompt:)`, `PromptID` and `cancelCurrentTurn()` are removed. The user decided on 2026-09-26: an agent is a long-running background tool. The Router design says the same (`generation-queue.md` §5.10: "the agent tool must start a child as a background run and return at once").

## What
1. **The `agents` tool is a Router `BackgroundTool`** (`Tool/AgentsTool.swift`, `Tool/AgentsToolOperations.swift`). A mount applies to the whole tool, so:
   - `var mount: ToolMount? { ToolMount(mode: .background) }`.
   - `start agent`: the background body starts the child run and waits for `run.result()` (a background body has a closed `ModelCallMark`, so this wait is legal). It returns the final message text as the run detail. The Router then posts `.completed`, and the pump delivers it to the parent as mail.
   - `list agents`, `check agent`, `cancel agent`: they end at once and settle inside `inlineSettleGrace` (a small named constant), so their answer comes back in their own envelope and is no mail. Example of this shape: `BackgroundChildAnswerTool` in the Router tests `GenerationQueueSubmissionTests.swift:81-108`.
   - `canceler(forCompletionToken:)` cancels the child run.
   - Remove `postFinalMessage` and the `ToolContext.post` of the final message (`Run/AgentRun+FinalMessage.swift`). `finalMessage(for:)` stays as the detail text.
2. **The run drives its session with the pump** (`Run/AgentRun.swift`, `Run/AgentRun+Children.swift`, `Run/AgentRun+TurnLimit.swift`):
   - The task prompt goes in with `send(_:)`. The run follows `streamSessionEvents()` for the whole run.
   - The run is idle, and thus ends, when: it has no open child run; each child's settled result was delivered (`runSettled` then a `submissionStarted` with cause `.mail`); the last `answered` has no `submissionStarted` after it; and no caller message waits. The final message is the text of that last answer. `mailDeliveryPaused` ends the run as a failure with a clear reason.
   - Remove the delivery-turn loop (`finishAfterChildren`, `dispatchFinalAnswer`) and the final-answer prompt. The pump starts the answer to the last child's mail, and that answer is the final answer.
   - `maxTurns` stays in this package: count passes from the live events (`generationCall`, `toolInvocation`) and correct the count from `entryRecorded` at each `submissionEnded`. Above the limit: `cancel()` the session, cancel the children, and end as `.failed(.hitMaxTurns)`.
   - `requestCancel` uses `cancel()` and cancels the child runs.
   - `AgentRunProgress` keeps working from the same stream.
3. Fix every other compile error that the removed symbols cause in `Sources`, `Examples/agents-demo`, `Tests` and `IntegrationTests`, with the smallest change that keeps the behavior. Task ^0mhzx3a does the host design, and task ^7f7z6qa does the documents.

## Acceptance Criteria
- [x] `swift build -Xswiftc -warnings-as-errors` passes with Router `c208add` or later, in the root and in `IntegrationTests/`.
- [ ] `start agent` returns at once with the Router pending envelope; the parent session gets the child's final message as mail with no driver call.
- [x] A parent and a child on the SAME model: the parent's submission ends after `start agent`, the child completes, and the parent answers from the mail (scripted test).
- [x] A run ends only when its session is idle as defined above; a run with two children ends after both results were delivered and answered.
- [x] `maxTurns`, `cancel agent`, `stop()` and `cancelRuns(caller:)` work as their tests say.
- [x] No use of `dispatchNextPrompt`, `enqueue(prompt:)`, `PromptID` or `cancelCurrentTurn` stays in code.

## Tests
- [x] Update `NestedRunTests*.swift`, `MaxTurnsTests*.swift`, `AgentsToolOperationsTests.swift`, `CheckAgentProgressTests.swift`, `AgentRunTests*.swift` to the new flow; add the same-model parent/child case.
- [x] Remove the different-slot workaround from the tests: runs on one model share its queue.
- [x] Run `swift test -Xswiftc -warnings-as-errors`. Expected: pass.
- [x] Run `cd IntegrationTests && swift test` 3 times. Expected: pass each time. Report the real results.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.