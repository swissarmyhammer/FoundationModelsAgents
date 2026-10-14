---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4x3dpxxywhrbjrzxtjz9rhe
  text: |-
    Peer proposal (after T1 started): the run puts the task prompt itself with the synchronous `try session.mail(Mail(sender: .user, body: .userMessage(prompt, options: stream)))`, keeps its MailID, and reads the task answer from that subscription. Then FIFO gives the order, and the gate goes away. If mail(_:) is not synchronous, or something else needs the gate, keep the gate and say why.

    Check results:
    - mail(_:) is nonisolated and synchronous (RoutedSessionActorQueueing.swift:26). It subscribes, then puts the mail in the queue. OK.
    - GAP 1, typed error: on this path a failed task answer gives only `AnswerFailure.reason = .error(String)`. The subscription and `awaitTerminal(of:)` give only the event. The raw error (for example `LanguageModelError.contextSizeExceeded`) is only in the private `outputHub` terminal, and only `streamEvents`/`respond` throw it (`throwIfFailed`). Thus `AgentRunFailure.contextOverflow` would become `modelFailed` (AgentRunTests+Failures pins it).
    - GAP 2, the window before begin: `make` returns the run before its answers start (the runner indexes the run before the session can call a tool), and `deliver` accepts messages in that window. The task prompt can go in the queue only in `drive`, after the follower subscribes (`streamSessionEvents()` is an actor call). A message from that window must wait until the task prompt is in the queue. Thus a small hold stays: it holds only until the synchronous mail of the task prompt in `drive`, and it opens at once after that (not at `submissionStarted`).
    Waiting for a decision on GAP 1.
  timestamp: 2026-10-14T11:40:36.157305+00:00
- actor: claude-code
  id: 01m4x3gapz9a1270p22v40wvmk
  text: |-
    Decisions (from the peer session):
    - GAP 1: option (a). Router part H adds a public `awaitAnswer(of id: MailID) async throws -> SessionAnswer`. It throws the original error of a failed answer (as respond(to:) does) and CancellationError for a cancelled mail. T2 puts the task prompt with mail(_:) and reads its end with awaitAnswer(of:). contextOverflow stays. Do not map the error text (option c).
    - Order of the work: first the parts that do not need part H (deliver(_:from:), the agent message text). The task prompt change waits for the message that part H is pushed.
    - GAP 2: keep a small hold for the window before begin. It opens at once after the synchronous mail of the task prompt in drive, not at submissionStarted. Add a fixed-order test: deliver before drive mails the task prompt; the task prompt is first in the queue and the message comes after it.
    - Router part G is pushed (head to follow). T3 can use it when T1 and T2 are done.
  timestamp: 2026-10-14T11:42:01.951896+00:00
- actor: claude-code
  id: 01m4x41d5je99679ffp8mc01t5
  text: 'Decision (FINDING A of T1): T1 uses the cause rule (`SubmissionStart.cause == .mail` of the first submission of a chain) inside the internal `MailAnswerFilter`, because `mailIds` now holds run mail too. No Router field. In T2, after part H, change the rule to ids: "the answer holds none of the user-type MailIDs that the run sent". The README and DocC (TheFinalMessage) sample shows a host, and a host has the MailID that send/mail returns, so the sample uses the id rule too, in T2.'
  timestamp: 2026-10-14T11:51:21.522793+00:00
- actor: claude-code
  id: 01m4x48bexz7r45m4abrhwbkh7
  text: 'Router part H is accepted: `awaitAnswer(of id: MailID) async throws -> SessionAnswer` on RoutedSession. `answered` gives the answer; `answerFailed` throws the original error (for example contextSizeExceeded); `cancelled` and `lost` throw CancellationError; close throws MailRefusal.closed. Each mail that one answer delivers gets that same answer. Router head to follow. After the T1 commit: move the Router pin to that head, then do the task prompt part of T2 (mail(_:) for the task prompt, awaitAnswer(of:) for its end, the small hold that opens after the mail).'
  timestamp: 2026-10-14T11:55:09.149862+00:00
depends_on:
- 01M4X3B3NWJT56QDGZXEKEVTB3
position_column: doing
position_ordinal: '80'
title: 'Mail step 3, T2: caller messages as mail by MailID'
---
## Plan (from the step 3 message)

Caller messages as mail. deliver(_:) and CallerMessageGate use try child.mail(Mail(sender: .session(senderID), body: .agentMessage(from: senderID, content: message))) and keep the MailID and the subscription. Use the session id of the sender when a session sends. Router renders an agent message as "[message from session <id>]" and the content, so remove the AgentsToolText.callerMessage prefix where this line replaces it, and update the pinned wording tests. The gate holds messages until the answer of the task prompt starts. The mail queue is FIFO and the task prompt is queued first. If FIFO gives the same guarantee, remove the gate; if not, keep it and say why. T2 does not depend on Router part G.

## Decision G3 (from T0)

Use `deliver(_ message: String, from sender: MailSender)`. `.session(id)` gives `.agentMessage(from: id, content:)`. `.user` gives `.userMessage(message, options: default)`, for a host that is not a session. Other senders (.run, .elicitation) are refused with a thrown error. The send agent tool passes `.session(callingSessionID)`. Keep the MailID that mail(_:) returns, for T3.

## Analysis before the work

FIFO does not give the guarantee alone: `streamEvents(to:)` puts the task prompt in the queue from its own task, after an await (`refuseWaitInsideOpenSubmission`). The run cannot know when the task prompt is in the queue. A message that `deliver` accepts before that time (also before `begin`) can come first. Thus the gate stays. The first `submissionStarted` is the first point where the run knows that the task prompt is in the queue.

#mail-step-3