---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
title: Fix the crash and restore review findings of the restore path
---
Items from the independent crash and restore review.

1. A restored child mails a short wake-up when its claim completed, and the full result when it did not.
2. A failed mark never looks marked; the rule for the result is written and tested.
3. The cancel reason is read when the drive returns; a run that finished before stop() is marked and mailed.
4. A cancel of a held run marks it cancelled, completes the claim, mails the caller, and closes the session. A held run does not stay open at stop().
5. The runner enforces parents first, with a typed error, and the depth is the real chain depth.
7. A caller that is the host root session gets claim completion through an environment closure.
9. claims(for:statuses:) matches the tool name too.
Docs: restore is not counted in maxConcurrentAgents; a crash between the mark and the mail is at-most-once; the host quit path uses stop(), never cancelRuns.