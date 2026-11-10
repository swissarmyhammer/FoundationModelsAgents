---
assignees:
- claude-code
position_column: done
position_ordinal: ff8d80
title: send caller only for a critical error that the agent cannot recover from
---
Seen live: a tester sent 11 "still running" messages in 5 min, each woke the root. The caller sentence of the agents tool description adds: each message wakes the caller; send one only for a critical error that you cannot recover from; your final report comes to the caller on its own when you are done. The example in DelegatingWithTheAgentsTool.md becomes an unrecoverable error. Test first: AgentsToolDescriptionTests pins the new sentence.