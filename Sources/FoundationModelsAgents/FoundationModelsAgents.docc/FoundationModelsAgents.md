# ``FoundationModelsAgents``

Load Claude-style sub-agents from a stack of folders and from marketplaces, and
run each agent in its own Router session.

## Overview

An agent is one Markdown file in an `agents/` folder. The YAML frontmatter
gives the name, the description, the tools, the model, and the other keys. The
body is the system prompt. The file name is the id of the agent:
`agents/code-reviewer.md` is `code-reviewer`.

```markdown
---
name: code-reviewer
description: Reviews code for quality and best practices.
tools: Read, Grep
model: flash
---

You are a code reviewer. Analyze the code and give specific feedback.
```

An agent run is a new Router session in the same process. The run gets a task,
works in the background with its own context and its own tools, and gives back
one final text. The caller keeps its own context.

The package has three layers:

- **``AgentDefinition``** decodes and validates one agent file.
- **``AgentRegistry``** keeps the catalog of the agent files over the local
  layers and the marketplace layers.
- **``AgentRunner``**, **``AgentRun``**, and **``AgentsTool``** start the runs,
  drive each Router session, and give a model one tool, `agents`, to delegate
  a task.

The host makes the dependencies: the `DotfolderStack`, the `MarketplaceStore`,
the `Router` and its resolved `LanguageModelProfile`, and the `SkillsRegistry`.
The host session and the sub-agents use the same instances.

### Skills and agents

Skills and agents are separate things. A skill is text that a model reads in
its current context. An agent is a new context with its own system prompt. An
agent uses skills through its `skills:` preload and through the `skills` tool.
The `skills:` key puts the body of each named skill into the instructions of
the run. The `skills` tool is one entry of the ``ToolCatalog``. To run a skill
in its own context, prompt an agent that has the `skills` tool to use the named
skill.

## Topics

### Essentials

- <doc:LoadingTheCatalog>
- <doc:RunningAnAgent>
- <doc:DelegatingWithTheAgentsTool>
- <doc:TheFinalMessage>

### The catalog

- ``AgentRegistry``
- ``AgentCatalog``
- ``AgentDefinition``
- ``AgentFrontmatter``
- ``AgentListing``
- ``AgentDiagnostic``
- ``AgentReloadReport``

### Runs

- ``AgentEnvironment``
- ``ToolCatalog``
- ``AgentRunner``
- ``AgentRun``
- ``AgentRunState``
- ``AgentRunFailure``
- ``AgentRunnerError``

### Delegation

- ``AgentsTool``
- ``AgentsToolContext``
- ``AgentsCLI``
