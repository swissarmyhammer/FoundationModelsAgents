---
assignees:
- claude-code
position_column: done
position_ordinal: ff9580
title: 'cancelActiveRuns(caller:): a cancel of the runs of a session that keeps its scheduled agents'
---
Seen in oneplan24 (django__django-13964): at the time limit session/cancel spared the background runs of the root, its coder kept a full Django suite running, and the harness killed the process after 600 s. ACPAgent will call Router cancelAll() and cancel the agent runs of the session. AgentRunner.cancelRuns(caller:) also ends the scheduled agents (right for a close, wrong for a cancel). Add cancelActiveRuns(caller:): cancels each run of the caller at once (a running firing too), keeps the scheduled tasks and their saved copy. Pin the cascade: the run's children and the background tool work of their sessions get a cancel.