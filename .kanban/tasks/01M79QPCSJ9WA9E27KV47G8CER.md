---
assignees:
- claude-code
position_column: done
position_ordinal: ff9c80
title: The pass count alone is no change for a repeated check agent
---
Seen live in hint24 (django-13925): the root checked a running double-check ~80 times; each check text had a new "Progress: N passes" count, so the "You checked this agent before, and nothing changed." sentence almost never came. A repeat check compares the text with no pass count; with no change it gives the sentence and the text with no count. The first check, and a check after the tools or the text changed, keep the count. No guard. Test first: CheckAgentRepeatTests.