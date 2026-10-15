---
assignees:
- claude-code
position_column: done
position_ordinal: de80
title: 'Elicitation task 33: child sessions are headless; AgentRun and agents-demo handle elicitation events'
---
From elicitation-plan.md, task 33 (phase 2).

Problem: AgentRun and agents-demo ignore `.elicitationRequested`. Thus a question in a child session waits forever. Until phase 4 (tasks 45 and 46), the question of a child does not go to a user.

Inputs on main: Extras 6a12b21 (`UserPresence`; a headless RunPlane answers each question at once with `.cancel(reason: RunPlane.noUserPresentReason)`, sends no event and stores no question; `ToolContext.userPresence`) and Router e24bd0a8 (`SessionConfiguration.userPresence`, default `.interactive`; a fork and a restore keep it, and a restore can override it).

Work:
1. Move the pins to Extras 6a12b21 and Router e24bd0a8 (root and IntegrationTests).
2. Write a short design, and get the acceptance of the peer session before code.
3. Implement it: the presence of each child session, the presence of the agents-demo root session, and what AgentRun does with an `.elicitationRequested` event that still comes.
4. Add tests in a fixed order: a child whose tool asks gets `cancel` with the reason, and the run ends normally.
5. Run the full suite one time. Push only after the peer accepts.

#elicitation-phase-2