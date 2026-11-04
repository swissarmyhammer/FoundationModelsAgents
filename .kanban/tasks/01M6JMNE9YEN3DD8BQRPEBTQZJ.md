---
assignees:
- claude-code
position_column: done
position_ordinal: fc80
title: Give the host the MailID of each message between a caller and a child
---
Blocker of ACP card ^nwsamy7 (send session_message for the messages between a caller and a child session). The ACP host must tell these messages apart. The MailID of a `send agent` or `send caller` call stays inside the agents tool.

## Facts (read in the code, 2026-11-04)
- `AgentRun.deliver` already returns `AgentRunMessageOutcome.delivered(MailID)` (commit 3984a94). The tool in `AgentsToolOperations.swift` drops the id: it returns only text (`AgentsToolAnswer` is `CorrectiveOutcome<String>`).
- Extras `Mail` holds `id`, `sender` (`MailSender.session(ULID)` or `.user`) and `body`.
- Router records the mail in the transcript as `MailRecord.mailDelivered(Mail)`. The type `MailRecordSegment` is internal. The public `SessionEvent.mailDelivered(MailID)` has the id only, no sender. The public `TranscriptEvent` has no mail id or sender field. So the host cannot read id and sender from the public recording. This needs a check by the ACP session.

## Options
1. Agents puts the MailID in the tool result and in the OperationEvent value (Extras `OperationValue`). Change is in Agents only. The result text stays the same for the model if the id goes into the event value, not the text.
2. The host reads the id and sender from the Router recording. Needs a public Router API. This is a Router change: it needs a Router card and a talk with the user first.

## Plan (no code before approval)
- Test first: a `send agent` call and a `send caller` call each push an OperationEvent value with the MailID, and it equals the id in the session of the receiver.
- Add a typed value for the sent message (mail id, direction, receiver run id). No message text in it (telemetry content rule).
- Keep the model-facing text unchanged.
- Update the docs (TheFinalMessage.md or the tool page) and README.

## Acceptance
- The host gets the MailID of every delivered message from the event value.
- A held message gives the id when accepted.
- Tests pass, review is clean.