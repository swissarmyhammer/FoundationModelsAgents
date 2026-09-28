# Delegating with the agents tool

Give a model the `agents` tool, so that the model can start agents, ask about
them, and cancel them.

## Overview

``AgentsTool`` is one `OperationTool` with the name `agents` and four
operations:

| Operation | Parameters | Answer |
|---|---|---|
| `list agents` | `filter?` | One `- name: description` line for each model-visible agent that matches. |
| `start agent` | `name`, `prompt` | At once: in a Router session, the pending envelope of the Router; outside one, "Agent `name` started with the id `id`." |
| `check agent` | `id?` | At once: the state of the run. With no `id`, one block for each run of the caller. |
| `cancel agent` | `id` | What the cancel did. |

The verb aliases are `stop` for `cancel`, `run` for `start`, `status` for
`check`, and `show` for `list`.

### The mount of each operation

`start agent` is a background run.
Its `@Operation` declares `ToolMount(mode: .background)`, thus in a Router
session the call answers at once with the pending envelope, and the run works
behind it. The `next` sentence of the envelope tells the model not to wait,
never to guess the result, and to end its answer. It also gives the
`check agent` call for the completion token of the call.
The final message comes to the calling session as mail.
The pump of the Router delivers it after the answer of the model ends (see
<doc:TheFinalMessage>). `list agents`, `check agent`, and `cancel agent` are
synchronous: each call gives its real answer in the same answer of the model.
No call waits for a time before it answers.

### Make the tool

```swift
let agentsTool = try await AgentsTool.make(context: AgentsToolContext(runner: runner))
let root = profile.standard.makeSession(instructions: "…", workingDirectory: projectURL,
                                        tools: [agentsTool] + otherTools)
```

``AgentsTool/make(context:catalogCharacterLimit:)`` reads the catalog of the
runner one time. The model-visible agents go into two places:

- The description holds fixed sentences on delegation, then the agents. The
  agent list uses the first form that fits `catalogCharacterLimit`: full
  `- name: description` lines, descriptions cut to 200 characters, names
  only, or as many names as fit and the count of the other agents. The fixed
  sentences are never cut.
- The schema makes the `name` field an enum of the same agents. Thus the model
  cannot invent a name.

Make a new tool for each session. After a reload, a changed agent runs with
the new definition, and a removed agent gives a corrective answer with the
current names. An added agent is in `list agents` and in the next tool, not in
the schema of this tool.

``AgentsToolContext/init(runner:allowedNames:)`` with `allowedNames` limits
the tool to those agents. The `Agent(a, b)` entry of a `tools` key gives the
same limit to the tool of a run.

### Answers are plain text

Each answer is plain text. A mistake of the model gives a corrective answer in
the same turn, never a thrown error. The corrective tells the model what was
wrong and what it can do now:

- An unknown or removed name, with the names that the model can start.
- A name outside `Agent(a, b)`.
- A blank prompt.
- A start when ``AgentEnvironment/maxConcurrentAgents`` runs have a turn in
  operation. The count does not include the run that calls `start agent`:
  after its answer, that run waits for the new child, and a run that waits holds
  no place. Thus with a limit of one, a parent and one child can work at one
  time. The runner keeps no queue: the model does the work itself, or starts
  the agent later.
- A start that makes a run deeper than ``AgentEnvironment/maxDepth``. A
  host-started run has depth one, and a child has the depth of its parent
  plus one.
- An unknown id, or the id of a run of a different caller, with the ids of
  this caller.

### Agents that start agents

Only an explicit `tools` entry gives the `agents` tool.
The entries are `Agent`, `Agent(a, b)`, and `agents`.
An agent with no `tools` key gets no `agents` tool.
It gets the other tools of the ``ToolCatalog``, thus it cannot start agents.
`disallowedTools: Agent` removes the tool. A run with one of these entries gets
its own `agents` tool when its depth is less than ``AgentEnvironment/maxDepth``.
A run at the depth limit gets no `agents` tool.

A run that starts agents finishes only after each of them ends. While it
waits, it holds no place in the run limit. The final message of each child
comes to the session of the parent as mail, and the pump of the Router starts
an answer of the parent to it. The parent can start more agents in that
answer. The parent ends when its session is idle: no child is open, the
parent answered each final message, and no message waits. The reply of its
last answer is its result. A cancel, or a failure of the parent, cancels its
children first.

### Skills through an agent

An agent uses skills through its `skills:` preload and through the `skills`
tool of the ``ToolCatalog``. To run a skill in its own context, start an agent
that has the `skills` tool, and tell it in the prompt to use the named skill.

### Not a code-mode surface

``AgentsTool`` does not conform to `OperationDescribing` or `ForkableTool`. A
run is a session with its own answers, and the final message needs a Router
session as the caller. Register the tool directly on a session.

### Slash commands and the command line

``AgentRunner`` conforms to `SlashCommandProviding`. It gives one command for
each user-invocable agent. A command starts a host-driven run with the text
after the name as the prompt, waits for it, and gives the final text.

``AgentsCLI/makeDriver(runner:)`` gives an `OperationCLIDriver` with the
commands `agents agent list`, `agents agent start`, `agents agent check`, and
`agents agent cancel`.
