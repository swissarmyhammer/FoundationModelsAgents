---
assignees:
- claude-code
position_column: done
position_ordinal: df80
title: 'mailDeliveryPaused: a better rule than cancelAll() of the whole run tree'
---
Found by the Router review of mailOnlyAnswerLimit.

Now: when the Router holds the mail (`mailDeliveryPaused`), `signal(after:on:)` gives `.mailDeliveryPaused` (Sources/FoundationModelsAgents/Run/AgentRun+Drive.swift, about line 307). `endState(after:on:)` then calls `session.cancelAll()` and ends the run as `.failed(.mailDeliveryPaused)` (about lines 195-197). Thus all child runs of the run, and their open questions (elicitations), are cancelled at once.

Work:
1. Decide a better rule. Examples:
   - End only the paused run, and give its held mail to the parent as a part of its result.
   - Keep the rule, and document that a big run tree needs a higher `AgentEnvironment.mailOnlyAnswerLimit`.
2. Implement the rule.
3. Add tests in a fixed order (gates or events; no time limit, sleep, clock wait, poll or retry).

Do not start this card before the peer session tells you to start it.

#elicitation-phase-3