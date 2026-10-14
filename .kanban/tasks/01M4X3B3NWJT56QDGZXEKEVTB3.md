---
assignees:
- claude-code
depends_on:
- 01M4X3AWSG1NMS3411854X04J6
position_column: done
position_ordinal: d580
title: 'Mail step 3, T1: port to the new Router API'
---
## Plan (from the step 3 message)

- streamSessionEvents() gives AsyncStream<SessionOutput>. The follower reads output.event and keeps output.origin.
- The public AgentEnvironment.RunEventObserver gets SessionOutput (the event and its origin), so a host can follow the id chain.
- session.cancel() becomes cancelAll() (cancelRequested, mailDeliveryPaused, the turn limit). Remove the cancel before close() in drive(): close() already does cancelAll().
- messageQueueDepth() → mailQueueDepth(); failure.messageIds → mailIds; send(_:) is synchronous, throws, and returns the MailID.
- Examples/agents-demo DemoModes.lines(for:): handle the new cases (mailDelivered, cancelled, lost, signalDone and the others).
- Commit with Agents green. Report the commit, the test result and each difference from the plan.

## Decision G2 (from T0)

Do not keep the strict depth check. Progress run mail starts no answer, so it can wait in the queue after the last answer, and then the run never goes idle (a hang that depends on timing). The idle rule reads only the user-type kinds of mailQueueDepth(): depthByKind for user_message, agent_message and elicitation_answer must be 0, and running must be empty. It ignores run_event in the depth. The run mail that matters (each child message and each child result) is tracked by MailID in T3. Until T3, keep the old text rule for run mail. Add a fixed-order test: a child posts progress after the last answer, and the run still goes idle.

## Decision G4 (from T0)

cancelAll() is nonisolated and does not wait, where cancel() was awaited. Agreed, no change.

## Record the Skills pin

FoundationModelsSkills had to update to main cf1ce54 (Package.resolved is gitignored). #mail-step-3