---
assignees:
- claude-code
position_column: todo
position_ordinal: '8780'
title: 'Note: an open toolInvocation record outside a submission sets the live turn count to one'
---
## Note (no work now)

Found in T4. `AgentRunTurns.apply(_:)` sets `hasToolOpen` for each open `SessionEvent.toolInvocation` record. When an open record comes outside any submission (for example, a tool that a background run mounts in the parent session), the live count of the run is at least one until the next `submissionStarted`. The count can then be one pass too high for that time, and the turn limit can trip early.

No case exists in Agents today: the `agents` tool posts no such record. Do the work only when a case appears. Then add a fixed-order test first, and count an open record only inside a submission (between `submissionStarted` and `submissionEnded`). #mail-step-3