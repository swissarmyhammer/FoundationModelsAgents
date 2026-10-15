---
assignees:
- claude-code
position_column: done
position_ordinal: dd80
title: 'MaxTurnsTests: the hitMaxTurns partial text of the lead is sometimes missing (CI 38580338505)'
---
CI run 38580338505 on ed5bfa2 (a kanban-only change) failed one test: "a lead with maxTurns 2 fails in its answer to the mail of its child with the text of that answer". MaxTurnsTests.swift:258: `partial?.contains(Self.helperText) == true` was false. The same code passed CI on 55aeae7 and passed locally. Find the race from the code and make the result deterministic. Do not run the test again and again. #bug #mail-new-events