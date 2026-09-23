---
name: unknown-disallowed-tool
description: An agent that denies a tool that no catalog holds.
disallowedTools: NoSuchTool
---

The one defect of this file: the `disallowedTools:` value `NoSuchTool` names
no tool of the catalog. The file gives a warning, and the loader shows it
first.
