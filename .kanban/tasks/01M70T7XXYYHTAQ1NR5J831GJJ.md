---
assignees:
- claude-code
position_column: done
position_ordinal: ff8580
title: 'Scheduled agents 3: the scheduler fires each task as a child run and mails each result'
---
`AgentScheduler`, owned by the `AgentRunner`, with an injectable clock.

- A task: id, name, agent (default `default`), prompt, spec, time zone, owner session, state (active/paused/ended), created, end (until, count, or created + 7 days for a recurring task), run/skip/miss counts, last result, next firing.
- Each firing starts a child run of the owner session through the runner, the same as a restored child (caller = owner, mail route), and the definition of the task's agent is read at firing time. The run holds a `childSession` lease in the owner's WorkRegistry while it runs; a pending task holds none.
- After every firing, the result is mailed to the owner with the task id, the name and the firing number.
- Overlap: a firing that is due while the previous run of the task is live is skipped and counted.
- Missed firings (sleep, or the process was down) run once, then the normal schedule goes on.
- pause, resume, cancel, run now.
- Closing the owner session (`cancelRuns(caller:)`) cancels its tasks. `stop()` stops the clock and keeps the saved tasks.
- Telemetry rows for create, fire, skip, cancel.

Tests with a manual clock. #scheduled-agents