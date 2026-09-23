# FoundationModelsAgents

[![CI](https://github.com/swissarmyhammer/FoundationModelsAgents/actions/workflows/ci.yml/badge.svg)](https://github.com/swissarmyhammer/FoundationModelsAgents/actions/workflows/ci.yml)
![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange.svg)
![Platform: macOS 27+](https://img.shields.io/badge/platform-macOS%2027%2B-lightgrey.svg)

[Claude Code-style sub-agents](https://code.claude.com/docs/en/sub-agents) for
[FoundationModels](https://developer.apple.com/documentation/foundationmodels):
load agent files from a stack of folders and from marketplaces, and run each
agent in its own [FoundationModelsRouter](https://github.com/swissarmyhammer/FoundationModelsRouter)
session.

An agent run is a new Router session in the same process. The run gets a task,
works in the background with its own context and its own tools, and gives back
one final text. The caller keeps its own context. A model starts agents through
one tool, `agents`, with four operations: `list agents`, `start agent`,
`check agent`, and `cancel agent`. An agent can have this tool too, thus agents
can start agents.

## The agent file

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
skills: [review]
---

You are a code reviewer. Read the code and give specific feedback.
```

- `name` and `description` are necessary. An agent with no valid description
  is not visible to the model.
- `tools` is the list of tools of the run. With no `tools` key, the run gets
  each tool of the `ToolCatalog`. `Agent(a, b)` lets the run start only the
  agents `a` and `b`. `disallowedTools` removes tools from the list.
- `model` is a Router slot (`standard` or `flash`) or a model reference of the
  profile. With no `model` key, a run that an agent starts uses the slot of
  that agent, and a run that the host starts uses the default slot of the
  `AgentEnvironment`.
- `skills` puts the body of each named skill into the instructions of the run.
- `maxTurns` limits the passes through the tool loop. `compactionPrompt` is
  the fold prompt of the agent.
- `disable-model-invocation: true` removes the agent from the `agents` tool.
  `user-invocable: false` removes its slash command.
- `$ARGUMENTS` in the body is the prompt of the run. The body can include
  partials with `{% include "house-rules.md" %}`.

The layers are, from lowest to highest: the marketplace layers, then
`defaults < user < project`. When two layers hold the same file, the highest
layer wins, and the registry records an advisory for each lower copy. A file
that is not valid gives a diagnostic, and the good files next to it load.

## Skills and agents

Skills and agents are separate things. A skill is text that a model reads in
its current context. An agent is a new context with its own system prompt. An
agent uses skills in two ways: the `skills:` key preloads the body of each
named skill into the instructions of the run, and the `skills` tool of the
`ToolCatalog` lets the run find and use a skill. To run a skill in its own
context, prompt an agent that has the `skills` tool to use the named skill.

## Usage

```swift
import FoundationModelsAgents
import FoundationModelsExtras
import FoundationModelsRouter
import FoundationModelsSkills
import Marketplace

// The host makes the dependencies: two dotfolder stacks and one marketplace store.
let agentStack = DotfolderStack(
    name: "agents",
    workingDirectory: projectDirectory,
    defaultsDirectory: shippedAgentsURL,
    userDirectory: userConfigURL)
let skillStack = DotfolderStack(
    name: "skills",
    workingDirectory: projectDirectory,
    defaultsDirectory: shippedSkillsURL,
    userDirectory: userConfigURL)
let market = MarketplaceStore(
    sources: [MarketplaceSource(marketplaceURL)],
    layout: SkillMarketplaceLayout.skills,
    cacheDirectory: cacheDirectory)

// The registry init reads no file. Start the store, then load the catalog.
let registry = AgentRegistry(
    marketplaces: market, stack: agentStack, variables: ["project": "acme"], watch: true)
await market.start()
try await registry.load()
let listing = registry.catalog().listing   // [AgentListing], one for each agent

// Skills are separate from agents. An agent uses skills through its
// `skills:` preload and through the `skills` tool.
let skills = SkillsRegistry(marketplaces: market, stack: skillStack, watch: true)
let skillsTool = try await SkillsTool.make(registry: skills)
var tools = ToolCatalog()
tools.register("skills") { skillsTool }

let environment = AgentEnvironment(
    profile: profile, skills: skills, workingDirectory: projectDirectory, tools: tools)
let runner = AgentRunner(registry: registry, environment: environment)

// Host-driven: start a run, then wait for its final text.
let run = try await runner.start("security-reviewer", prompt: "Review Sources/Parser.swift.")
let review = try await run.result()

// Model-driven: a root Router session gets the agents tool.
let agentsTool = try await AgentsTool.make(context: AgentsToolContext(runner: runner))
let root = profile.standard.makeSession(
    instructions: "You give work to agents with the agents tool.",
    workingDirectory: projectDirectory,
    tools: [agentsTool])
let events = await root.streamSessionEvents()   // subscribe before the first turn
for try await _ in await root.streamEvents(to: "Ask code-reviewer to review Sources/Parser.swift.") {}

// `start agent` returns at once. When the run ends, its final message
// is staged in the root session, and the next turn reads it.
_ = await events.first { event in
    if case .runSettled = event { true } else { false }
}
let answer = try await root.dispatchNextPrompt()

// The Router does not know the runs of a session: cancel them before close().
await runner.cancelRuns(caller: root.id)
await root.close()
```

`profile` is the `LanguageModelProfile` that the host Router resolves. The
runs and the root session use the same profile, thus the same models. The
registry, the skills registry, and the store are the same instances for the
host session and for each run.

The registry reads the files in `load()`, not in its init. Call `load()` after
`market.start()`, thus the catalog holds the agents of the marketplace. With
`watch: true`, the registry builds the catalog again when a file changes, and
`registry.onReload` gives each new catalog.

A run that the host starts gives its final text to `result()`. A run that a
model starts with `start agent` posts one final message into the calling
session. The Router records the message and sends a `runSettled` event, and
the next prompt of the session reads the message. Thus the host calls
`dispatchNextPrompt()` after the event. `AgentRunner` is also a
`SlashCommandProviding`: each agent that the user can start is one slash
command.

[`Tests/FoundationModelsAgentsTests/ReadmeExampleSource.swift`](Tests/FoundationModelsAgentsTests/ReadmeExampleSource.swift)
holds a copy of this example. `ReadmeExampleTests` compares the two texts, and
runs the copy with a scripted profile over the fixture library. Thus this
example compiles and runs.

## Install

macOS 27 or later. The package is not on a registry. Add it to the
dependencies of your `Package.swift` as a git dependency on the `main` branch
of `git@github.com:swissarmyhammer/FoundationModelsAgents.git`, and add the
`FoundationModelsAgents` product to your target.

## Documentation

- The DocC catalog in
  [`Sources/FoundationModelsAgents/FoundationModelsAgents.docc`](Sources/FoundationModelsAgents/FoundationModelsAgents.docc)
  has articles on the catalog, the runs, the `agents` tool, and the final
  message.
- [`docs/skills-and-agents.md`](docs/skills-and-agents.md) tells what
  transfers from skills to agents, how one plugin gives skills and agents,
  and the partials rule.
- [`Examples/agent-library`](Examples/agent-library) is a fixture library with
  local layers, a marketplace, and broken files. The tests and the demo use it.
- [`Examples/agents-demo`](Examples/agents-demo) is the demo executable:
  `--chat`, `--fan-out`, `--watch`, and `--marketplace`.
- [`plan.md`](plan.md) is the full design.
