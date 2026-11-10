---
assignees:
- claude-code
position_column: done
position_ordinal: ff8b80
title: 'A repeated check agent with no change gives one short text: do not check again, post your status'
---
From the ACPAgent session (bench run planner24, django__django-14752, root 01M72...KRBJHK, about seq 39225–40400). The root checked two running planners in alternation 60 times in one answer. That cost 39 generations of 37–42K tokens each and 679 s of model time on the shared model. Each repeat returned "You checked this agent before, and nothing changed." followed by the full still-working text.

Fix (option a): a repeat check by the same caller with no change now returns AgentRun.repeatedCheckText alone. It is short, carries no progress block, says "Do not check it again", and ends with "If no work is left, post your status as plain text now: what you wait on." The wording follows the no-turn-language rule. Tests: CheckAgentRepeatTests, including two agents checked in alternation. #bug