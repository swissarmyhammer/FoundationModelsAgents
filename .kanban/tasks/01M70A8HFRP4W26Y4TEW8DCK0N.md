---
assignees:
- claude-code
position_column: done
position_ordinal: ff8180
title: AgentRegistry takes the session template context, and each body renders with it
---
FoundationModelsSkills 560dbaf gives each skill render a `templateContext: [String: TemplateValue]` (`tools.<group>.enabled`). Agent bodies must render with the same context, so a body can gate a section with `{% if tools.kanban.enabled %}`.

- Each public AgentRegistry init takes `templateContext: [String: TemplateValue] = [:]`.
- AgentBodyRenderer passes it as `values:` to StenciledDotfolderStack (Extras f647455).
- Test: a body with `{% if tools.kanban.enabled %}` renders its section only when the context says so. #root-prompt