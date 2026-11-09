---
assignees:
- claude-code
position_column: done
position_ordinal: ff8480
title: 'Scheduled agents 2: normalize an English schedule with the flash slot'
---
`AgentScheduleNormalizer` protocol, and an implementation on `AgentEnvironment.selectionModel` (the flash slot, as the agent search uses it). It gets the text, the time zone and the current time, and answers a guided `@Generable` value: a cron text, an ISO date-time, an `every N unit` interval, or ambiguous with a reason. The answer is parsed with card 1, so a bad model answer is refused, never used. Ambiguous text is refused with a correction. With no selection model, English is refused with a correction that names the direct forms.

Tests with a stub normalizer and with a scripted model. #scheduled-agents