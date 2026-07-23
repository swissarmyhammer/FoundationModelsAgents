---
depends_on:
- 01KY7EW9GVWFSP0WA5VXVW26RQ
position_column: todo
position_ordinal: '8180'
title: 'M1: AgentDefinition parsing + validation over Extras'' FrontmatterDocument'
---
Plan §14 M1, re-targeted per the plan-rework task: AgentDefinition parsed from frontmatter *.md agent files using Extras' FrontmatterDocument.split (SHIPPED) with whole-file untrusted render through Extras' TemplateEngine first (render-then-parse, the family rule); field validation (name, description, model, tools allowlist, color/aliases per plan §4-5) with hard, located errors; hermetic fixture tests. No Skills dependency — the substrate is Extras.