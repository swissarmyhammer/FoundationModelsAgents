---
depends_on:
- 01KY7EWTVAPKBJ6222AA321Z6Y
- 01KY7EWTVREE0SPZ5S19C2DQ86
position_column: todo
position_ordinal: '8480'
title: 'M4: AgentsTool — the fused agents OperationTool'
---
Plan §14 M4 / §1: one fused OperationTool named agents (FoundationModelsOperationTool pattern, built), six ops sharing one noun: list agents / search agent / start agent / check agent / send agent / cancel agent — all delegation background (§8). Construction-time binding: the tool captures the Router (and registry) at construction — FM hands tools arguments only, so a tool cannot discover its caller (plan decision #19). Every lifecycle op returns a typed AgentEvent that lands in the calling session's transcript as a structured segment (§8.2). Depends on M2 (registry) + M3 (runs).