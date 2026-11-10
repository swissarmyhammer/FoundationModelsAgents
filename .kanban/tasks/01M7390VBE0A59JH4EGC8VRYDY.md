---
assignees:
- claude-code
position_column: done
position_ordinal: ff8c80
title: Revert the repeat check agent short text (643cfdb)
---
The user wants no tool guards for polling; the rule lives in the skills (house-rules partial). Revert 643cfdb (^4ys0a29): a repeated check agent with no change gives the earlier "You checked this agent before, and nothing changed." sentence then the full still-working text. Test first: restore CheckAgentRepeatTests from before 643cfdb, see it fail, then restore AgentRun+FinalMessage.swift and the doc in AgentsToolOperations.swift.