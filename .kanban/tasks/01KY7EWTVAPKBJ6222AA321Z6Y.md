---
depends_on:
- 01KY7EW9GVWFSP0WA5VXVW26RQ
position_column: todo
position_ordinal: '8280'
title: 'M2: AgentRegistry over Extras'' DotfolderStack'
---
Plan §14 M2, re-targeted: stacked discovery of agent definition files via DotfolderStack.enumerate (user ~/.config/<name>/agents/ < project .<name>/agents/, nearest wins, per-item source tracking for diagnostics), recursive/flat file entries, name collisions logged with layer provenance, re-scan on demand. Registry is pure data over Extras — no file I/O outside the stack. Depends on M1 for the parsed type.