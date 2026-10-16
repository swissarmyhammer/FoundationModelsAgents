# Delegating with the agents tool

Give a model the `agents` tool, so that the model can find agents, start them,
ask about them, cancel them, and send messages to them.

## Overview

``AgentsTool`` is one `OperationTool` with the name `agents` and seven
operations:

| Operation | Parameters | Answer |
|---|---|---|
| `list agents` | `filter?` | One `- name: description` line for each model-visible agent that matches. |
| `find agents` | `query`, `limit?` | One `- name: description` line for each agent that the search finds, best first. The default `limit` is 5. |
| `start agent` | `name`, `prompt`, `workingDirectory?` | In a Router session: the final message when the run ends in the settle period of the session, else the pending envelope of the Router. Outside one, at once: "Agent `name` started with the id `id`." |
| `check agent` | `id?` | At once: the state of the run. With no `id`, one block for each run of the caller. |
| `cancel agent` | `id` | What the cancel did. |
| `send agent` | `id`, `message` | At once: "The message was sent to Agent `name` (`id`)." The run answers the message before it ends. |
| `send caller` | `message` | At once: the message was sent to the session that started the run. The run continues. |

The verb aliases are `stop` for `cancel`, `run` for `start`, `status` for
`check`, and `show` for `list`. The noun alias is `parent` for `caller`.
`send parent` is the same call as `send caller`.

The `workingDirectory` field of `start agent` names the working folder of the
new run. With no field, the new run works in the folder of its creator, the
session that makes the call: a child of a run works in the folder of its
parent, and a run that a host session starts, when that session is not a run,
works in ``AgentEnvironment/workingDirectory``. A relative path starts from
that same folder. The new run never works in the folder of its agent by
default. See "The working folder of a run" in <doc:RunningAnAgent>.

### Find an agent

`find agents` selects agents by a search of their descriptions (decision D61).
A model calls it with the task, or the kind of work, as the query:

```json
{"op": "find agents", "query": "write unit tests for the parser"}
```

The search does the same steps as the `search skill` operation of the
`skills` tool, with the same parts of FoundationModelsSkills:

1. A `MetadataSearcher` ranks the descriptions with keywords and with the
   cosine of the embedding. The embedding model is the `embedding` slot of the
   profile.
2. The selection model picks the best matches among the candidates. It is the
   `skillsSelectionModel` of
   ``AgentEnvironment/make(profile:skills:skillsSelectionModel:skillsCatalogCharacterLimit:skillsVisibility:workingDirectory:tools:defaultSlot:maxConcurrentAgents:maxDepth:maxRetainedRuns:budget:tracer:logger:metricsFactory:inlineSettleGrace:runEventObserver:)``.
   With no selection model, the call gives the rank of step 1. When the answer
   of the selection model does not decode, the rank of step 1 answers the call,
   and the call does not fail.

The index holds only the model-visible agents, thus an agent with no valid
description, and an agent with `disable-model-invocation: true`, are never
found. The call then keeps only the agents that the tool can start: the tool of
a run does not give the agent of that run, and `Agent(a, b)` gives only `a` and
`b`. The answer has one `- name: description` line for each match, best first,
then the sentence that tells how to start an agent. With no match, the answer is
"No agent matches this search. Do the task yourself."

``AgentRunner`` holds one index for the tools of the host session and of each
run. The index follows each catalog of `AgentRegistry.onReload`, thus an agent
that a reload adds is found, also by a tool that was made before the reload.

### Messages between a run and its caller

A caller can send a message to a run that it started while the run works.
The `id` is the id of the run, or the completion token of the `start agent`
call:

```json
{"op": "send agent", "id": "<id>", "message": "Also check the error paths."}
```

The run holds a message that comes before its task prompt is in the mail
queue, and mails it at once after the task prompt. Thus the session of the
run gets the message after the task prompt. The run answers
each message that it accepted before it ends, and its final message still
comes to the caller as mail. A run that ended gets no message: the call gives
the corrective "The run `id` ended (`state`), and it gets no more messages.
Start a new run." An id of a run of a different caller gives the corrective of
an unknown id.

A run with a caller can send a message to that caller while it works:

```json
{"op": "send caller", "message": "I found two errors. I continue with the tests."}
```

The message comes to the session of the caller as mail
(`SessionEvent.runMessage(_:)`), and the pump of the Router starts an answer
to it. The run continues to work. A run that started agents answers each
message of a child before it ends. The answers to messages count toward
`mailOnlyAnswerLimit` in the same way as the answers to final messages. When
the Router holds that mail and starts no answer for it, the run pauses: it
waits until each run that it started ended, then it fails with
``AgentRunFailure/mailDeliveryPaused(_:)`` and the held results (see
<doc:TheFinalMessage>). A message from its caller ends the hold. A session that has no caller, for
example a host session or a host-started run, gets the corrective "You have
no caller."

A `send agent` call to a run of the caller, and a `send caller` call with a
message, write one `agent.message.sent` log record and span event. The record
holds the direction (`to_run` or `to_caller`), the outcome (`delivered`,
`ended`, or `no_caller`), and the length of the message. It never holds the
text of the message.

### The mount of each operation

`start agent` is a background run.
Its `@Operation` declares `ToolMount(mode: .background)`, thus in a Router
session the call waits for the run up to the settle period of the session. A
run that ends in that time gives its final message as the answer of the call.
A run that continues gives the pending envelope, and works behind it. The
tool states no settle period of its own: the host sets it with
`SessionConfiguration.inlineSettleGrace`, and for the sessions of the runs
with `AgentEnvironment.make(inlineSettleGrace:)`.
The `next` sentence of the envelope names the run by its completion token.
The mail of the final message names the run by the same token. Then the
sentence tells the model that the envelope is not the result, and not to call
a tool to wait or to check. The model does other work that does not need the
result, or else it does nothing. The tool description does not tell the model
to call `check agent` for a run in the background.
The final message comes to the calling session as mail. The session injects
it as a new message, and that message starts the model again (see
<doc:TheFinalMessage>). `list agents`, `find agents`, `check agent`,
`cancel agent`, `send agent`, and `send caller` are synchronous: each call
gives its real answer in the same answer of the model.

### Make the tool

```swift
let agentsTool = try await AgentsTool.make(context: AgentsToolContext(runner: runner))
let root = profile.standard.makeSession(
    configuration: SessionConfiguration(instructions: "…", workingDirectory: projectURL,
                                        tools: [agentsTool] + otherTools, userPresence: .headless))
```

A host with no UI for questions makes its root session headless: a question
of the session then ends at once with a cancel and a reason.

The session of a run takes the user presence of the session whose
`start agent` call started it. The run sends each question of its session to
that session, one level up (`SubagentQuestionRelay` of the Router). Thus the
root session of the host gets the question of a run at any depth as
`SessionEvent.elicitationRequested(_:)`, with the same id and with the names
of the agents in `agentPath`. The host answers it on the root session with
`respond(elicitationId:response:)`, and the answer goes down to the run that
asked. A cancel of the run, `cancelAll()`, or `close()` of a session on the
way ends the question one time at each level. Under a headless root session,
each run session is headless too, thus its question ends at once with a
cancel. A host-started run is headless.

``AgentsTool/make(context:catalogCharacterLimit:)`` reads the catalog of the
runner one time. The model-visible agents go into two places:

- The description holds fixed sentences on delegation, then the agents. The
  fixed sentences tell the model to compare each task with the description
  of each agent, and to give the task to the agent whose description
  matches it, in place of doing the task itself. When the list does not show
  all the agents or their descriptions, or no listed agent matches, the model
  calls `{"op": "list agents"}`. When no agent matches after that, the model
  does the task itself. The model puts the full task in the
  `prompt`, because the agent sees only that prompt. Each call in the text
  names the tool `agents`, and the text tells that the value of `op` is not
  the name of a tool. The agent list uses the first form that fits
  `catalogCharacterLimit`: full `- name: description` lines, descriptions
  cut to 200 characters, names only, or as many names as fit and the count
  of the other agents with the `list agents` call. The fixed sentences are
  never cut.
- The schema makes the `name` field an enum of the same agents. Thus the model
  cannot invent a name.

Make a new tool for each session. After a reload, a changed agent runs with
the new definition, and a removed agent gives a corrective answer with the
current names. An added agent is in `list agents` and in the next tool, not in
the schema of this tool.

``AgentsToolContext/init(runner:allowedNames:)`` with `allowedNames` limits
the tool to those agents. The `Agent(a, b)` entry of a `tools` key gives the
same limit to the tool of a run.

The tool of a run does not offer the agent of that run. Its description,
`list agents`, and the `name` enum do not hold that agent. A `start agent`
call with its name gives the corrective "You cannot start the agent `name`,
because it is your own agent. Do this task yourself." with the names that the
tool can start. A `send agent` call with the id of the run gives the corrective
"The id `id` is the id of your own run. You cannot send a message to your own
run." Thus a model of a run cannot give its own task to a new run of its own
agent. The tool of a host session is not a run, and it offers each agent.

### Answers are plain text

Each answer is plain text. A mistake of the model gives a corrective answer in
the same turn, never a thrown error. The corrective tells the model what was
wrong and what it can do now:

- An unknown or removed name, with the names that the model can start.
- A name outside `Agent(a, b)`.
- A blank prompt.
- A blank query of `find agents`, or a `limit` below one.
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

Only an explicit `tools` entry gives the operations that start agents.
The entries are `Agent`, `Agent(a, b)`, and `agents`.
An agent with no `tools` key gets only the message operations, and only in a run with a caller.
It gets the other tools of the ``ToolCatalog``, thus it cannot start agents.
Each run gets its own instance of the tool. This table gives the operations
of the tool of a run:

| The run | The operations of its `agents` tool |
|---|---|
| An `Agent` entry, and a depth less than ``AgentEnvironment/maxDepth`` | Each operation |
| An `Agent` entry at the depth limit, and a caller | `send agent` and `send caller` |
| No `Agent` entry, and a caller | `send agent` and `send caller` |
| Each other case, for example a host-started run with no `Agent` entry | No `agents` tool |

A run has a caller when a `start agent` call started it. A host-started run
has no caller. `disallowedTools: Agent` removes the tool in each case. The
tool with only the message operations does not read the catalog, and its
description names no agent. The description of the tool of a run with a
caller ends with the id of the caller session and the `send caller` call.
When each run of an agent is at the depth limit, `runner.catalog()` gives a
warning for its `Agent` entry: a run with a caller gets only the message
operations, and a host-started run gets no `agents` tool.

A run that starts agents finishes only after each of them ends. While it
waits, it holds no place in the run limit. The final message of each child
comes to the session of the parent as mail, and the pump of the Router starts
an answer of the parent to it. The parent can start more agents in that
answer. The parent ends when its session is idle: no child is open, each
final message and each message of a child has a terminal event (usually its
answer), and no message waits. The reply of its last answer is its result. A cancel, or a
failure of the parent, cancels its children first.

### Skills through an agent

An agent uses skills through its `skills:` preload and through the `skills`
tool that ``AgentEnvironment`` puts in the ``ToolCatalog``.
To run a skill in its own context, start an agent that has the `skills` tool,
and tell it in the prompt to use the named skill.

### Not a code-mode surface

``AgentsTool`` does not conform to `OperationDescribing` or `ForkableTool`. A
run is a session with its own answers, and the final message needs a Router
session as the caller. Register the tool directly on a session.

### Slash commands

``AgentRunner`` conforms to `SlashCommandProviding`. It gives one command for
each user-invocable agent. A command starts a host-driven run with the text
after the name as the prompt, waits for it, and gives the final text. The run
works in the folder of the session that runs the command: the
`workingDirectory` of the `SlashCommand.Invocation`. See "The working folder
of a run" in <doc:RunningAnAgent>.
