---
assignees:
- claude-code
position_column: done
position_ordinal: ff8880
title: start agent takes `agent` as an alias of `name`, and schedule agent takes `name` for its agent
---
Seen live in bench run planner24 (django__django-13447, root session …4A6KXE, seq 116): `{"op": "start agent", "agent": "planner", "prompt": "..."}` gave "Missing required parameter(s): name." twice. In the fused schema, `schedule agent` names its agent `agent`, and `start agent` names it `name`, so the model mixes them.

- `start agent`: `agent` (and agent_name, subagent, subagent_type, agent_type) is an alias of `name`.
- When `name` and an alias are both given and differ, refuse with a correction; when they are equal, take it.
- `schedule agent`: `name` is an alias of `agent`, not of `title` (title keeps label, task_name, schedule_name).
- Tests with the exact call above. #forgiving-tools