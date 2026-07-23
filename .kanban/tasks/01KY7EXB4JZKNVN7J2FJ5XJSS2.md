---
depends_on:
- 01KY7EW9GVWFSP0WA5VXVW26RQ
- 01KY7EXB3XC59AEH6JFDVKD31E
position_column: todo
position_ordinal: '8580'
title: 'M5: scheduler + observability over Router''s state'
---
Plan §14 M5 per the reworked §8: AgentRunner admission (max concurrent agents as a policy gate ABOVE Router's per-model serialGate — the gate serializes generate calls; admission bounds how many runs exist at all), send agent / cancel agent lifecycle, per-run observation binding Router's @Observable per-session state (Router ekd82f4 — absorbs what §8.1/8.3 wanted) and live progress from the rich event stream. Notification turns (§8.4-8.5 waiting-without-blocking) and display correlation ride the AgentEvent segments. DEPENDS also on M4.