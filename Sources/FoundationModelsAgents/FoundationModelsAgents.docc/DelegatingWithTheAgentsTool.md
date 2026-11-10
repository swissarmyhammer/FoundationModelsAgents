# Delegating with the agents tool

Give a model the `agents` tool, so that the model can find agents, start them,
ask about them, cancel them, write them, and send messages to them.

## Overview

``AgentsTool`` is one `OperationTool` with the name `agents`. These are its
operations on agents and on runs. The schedule operations are in
"Scheduled agents" below.

| Operation | Parameters | Answer |
|---|---|---|
| `list agents` | `filter?` | One `- name: description` line for each model-visible agent that matches. |
| `find agents` | `query`, `limit?` | One `- name: description` line for each agent that the search finds, best first. The default `limit` is 5. |
| `start agent` | `name`, `prompt`, `workingDirectory?` | In a Router session: the final message when the run ends in the settle period of the session, else the pending envelope of the Router. Outside one, at once: "Agent `name` started with the id `id`." |
| `check agent` | `id?` | At once: the state of the run. With no `id`, one block for each run of the caller. |
| `cancel agent` | `id` | What the cancel did. |
| `add agent` | `name`, `content`, `layer?` | The file that the add wrote and its layer, then the diagnostics of the agent. See "Writing agents" below. |
| `edit agent` | `name`, `content`, `document?`, `layer?` | The file that the edit wrote and its layer. After an edit of `AGENT.md`, also the diagnostics of the agent. |
| `remove agent` | `name`, `layer?` | Each folder that the remove deleted, and its layer. |
| `send agent` | `id`, `message` | At once: "The message was sent to Agent `name` (`id`)." The run answers the message before it ends. |
| `send caller` | `message` | At once: the message was sent to the session that started the run. The run continues. |

The verb aliases are `stop` for `cancel`, `run` for `start`, `status` for
`check`, `show` for `list`, `create` and `new` for `add`, `update` and
`change` for `edit`, and `delete`, `rm` and `del` for `remove`. The noun alias is `parent` for `caller`.
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
   ``AgentEnvironment/make(profile:skills:skillsSelectionModel:skillsCatalogCharacterLimit:skillsVisibility:workingDirectory:tools:defaultSlot:maxConcurrentAgents:maxDepth:maxRetainedRuns:budget:tracer:logger:metricsFactory:inlineSettleGrace:runEventObserver:callerMail:instructionsPreamble:sandboxProbe:)``.
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

A run with a caller can send a message to that caller while it works. Each
message wakes the caller, thus the caller sentence of the tool description
tells the model to send one only for a critical error that it cannot recover
from. The final message of the run comes to the caller on its own:

```json
{"op": "send caller", "message": "Blocked: the test database does not start (OperationalError: could not connect to server). I cannot go on."}
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

A message that goes out as mail also gives the host a typed record. The call attaches it to
its tool-call report with the schema name `FoundationModelsAgents.AgentMessageSent`, and the
host reads it from `SessionEvent.toolCallReport`. The model never sees it, and it holds no
text of the message. The JSON document has these keys:

| Key | Type | Meaning |
|-----|------|---------|
| `mailId` | string | The ULID of the mail in the session of the receiver. |
| `direction` | string | `toChild` for `send agent`, `toCaller` for `send caller`. |
| `receiverRunId` | string, only for `toChild` | The id of the run that got the message. |
| `receiverSessionId` | string | The ULID of the session that got the mail. |

A `send caller` call over the `start agent` call route (a caller that is a host session) posts a
`message` event and makes no mail, so it attaches no record.

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
`cancel agent`, `add agent`, `edit agent`, `remove agent`, `send agent`, and
`send caller` are synchronous: each call gives its real answer in the same
answer of the model.

### The work of a run in the calling session

A run is one more background tool call of the calling session. The
`start agent` call holds one `WorkKind.childSession` lease in the
`WorkRegistry` of the calling session, with the id of the session of the
run. The lease opens before the run gets its task prompt. It ends when the
session of the run has no work (its `workEnded` event), and a new lease opens
when that session gets new work again. While the run waits only for the user,
the lease is suspended, thus the calling session has no work, and the answer
resumes the lease. The lease ends when the run ends: its session closed,
failed, or was cancelled, also by a cancel or a close of the calling session.
The work of the run, for example a lease of one of its tools, stays in the
registry of the session of the run.

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
  fixed sentences tell the model to give an agent a whole unit of work: work
  that needs many reads, a long output, or a loop of fixes and tests. The
  model does a task of one step itself. It gives the work to the agent whose
  description matches it. When the list does not show all the agents or their
  descriptions, or no listed agent matches, the model calls
  `{"op": "list agents"}`. When no agent matches after that, the model does
  the work itself. The model puts the full task in the `prompt`, because the
  agent sees only that prompt, and tells an agent that changes files to
  commit after each step that works, so that each commit is a point to undo
  to. Each call in the text
  names the tool `agents`, and the text tells that the value of `op` is not
  the name of a tool. The agent list uses the first form that fits
  `catalogCharacterLimit`: full `- name: description` lines, descriptions
  cut to 200 characters, names only, or as many names as fit and the count
  of the other agents with the `list agents` call. The fixed sentences are
  never cut.
- The `name` field of the schema is a plain string. `start agent` checks the
  name against the live catalog when the call runs.

Make a new tool for each session. The description stays as it was made, thus
the tool definition is the same for the whole session. After a reload, a
changed agent runs with the new definition, an added agent is in
`list agents` and `start agent` starts it, and a removed agent gives a
corrective answer with the current names.

The tool is `CatalogNoticing` (FoundationModelsExtras). Each session that
mounts it through `ToolMounting.makeWrapped`, a child session too, joins its
`catalogNoticeBoard`. A reload that adds or removes an agent that the tool can
start, or changes its description, posts one `CatalogChangeNotice` of the
`agents` kind to each of those sessions, for example
"Agents changed. New: `coder`: Writes and tests code." A reload that changes
only a body, or only an agent that the tool cannot start, posts nothing. Each
tool compares its own agents, thus a tool with `Agent(a, b)` announces only
`a` and `b`. A reload before a session mounts the tool reaches no session.

The tool is also `AgentLaunching` (FoundationModelsExtras). A host that casts
a tool of a session to it reads ``AgentsTool/launchableAgents()``: the agents
that the tool can start now, in catalog order, as `CatalogEntry` values with
the description on one line. The list reads the current catalog, thus it
follows reloads, and it applies the same limits as `start agent`: the allowed
names, and not the agent of the run. A tool with only the message operations
gives an empty list, and so does an empty catalog. The Router uses the list to
name an agent in its hint to delegate.

``AgentsToolContext/init(runner:allowedNames:)`` with `allowedNames` limits
the tool to those agents. The `Agent(a, b)` entry of a `tools` key gives the
same limit to the tool of a run.

The tool of a run does not offer the agent of that run. Its description,
and `list agents` do not hold that agent. A `start agent`
call with its name gives the corrective "You cannot start the agent `name`,
because it is your own agent. Do this task yourself." with the names that the
tool can start. A `send agent` call with the id of the run gives the corrective
"The id `id` is the id of your own run. You cannot send a message to your own
run." Thus a model of a run cannot give its own task to a new run of its own
agent. The tool of a host session is not a run, and it offers each agent.

### The GraphQL endpoint

The tool is also `GraphQLEndpointTool` (FoundationModelsExtras). Its
`graphQLEndpoints` is one endpoint, ``AgentsGraph``: the `agents` endpoint,
version `1`, with the scope `sessionFolder`. The endpoint gives the
`agents`, `agent(id:)`, and `diagnostics` queries over the catalog of the
registry of the runner, the same catalog that `list agents` reads. Thus a
reload shows in the endpoint and in `list agents`. A host finds the endpoint
in the tools of a session, which it holds as `any Tool` values:

```swift
let endpoints = sessionTools.compactMap { $0 as? any GraphQLEndpointTool }.flatMap(\.graphQLEndpoints)
```

A host with no `agents` tool, for example before a session starts, gets the
same endpoint from its registry:

```swift
let endpoint = try registry.agentsGraph()
```

The registry makes the endpoint one time (EXTRAS-9 rule 1). Each `agents`
tool over one registry, of each session and each run, gives the same
instance. The endpoint reads the catalog of the registry, and it does not
keep the registry. A tool with only the message operations gives the
endpoint too: the endpoint reads the catalog of the session folder, not the
grant of the model, and a host lists the endpoint of the session folder, not
of one run.

The root `cursor` query and the `changes(after:)` subscription give the
changes of the catalog (EXTRAS-9 rule 9). Each reload that adds, changes, or
removes an agent gives one `AgentChange` with the ids in `added`, `changed`,
and `removed`; a reload that changes nothing gives none. A client reads
`agents` and `cursor`, then subscribes after that cursor, and queries
`agent(id:)` again for each added or changed id. The registry has one change
log, thus each endpoint over the registry gives the same cursor, and a
`reload()` returns after its change is in the log. A cursor of another run of
the host, a cursor that is too old for the log, or a cursor after the newest
change gives `RESYNC_REQUIRED`. `agentChanges` and `agentsChanges` name
`changes`, and `since` names `after`.

The model sends no GraphQL text to the tool. The name, the description, and
the schema of the tool do not change.

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

Each operation includes `add agent`, `edit agent`, and `remove agent`. Thus a
run with an `Agent` entry under the depth limit can write agents too. No gate
stands in front of a write (D87).

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

## Writing agents

The tool also makes, changes, and removes agents (AG-9, D87, D175). The
writes go to `AgentWriter` over the local layers of the registry of the
runner. After each write that the writer does, the registry reloads. Thus a
`start agent` call in the same session starts the new agent, and the next
`list agents` call shows the change.

| Operation | Fields | What it does |
|---|---|---|
| `add agent` | `name`, `content`, `layer?` | Writes a new agent: `<layer root>/<name>/AGENT.md` with `content` as its full text. |
| `edit agent` | `name`, `content`, `document?`, `layer?` | Replaces the full text of one document of the agent with `content`. |
| `remove agent` | `name`, `layer?` | Deletes the agent folders of the agent in the layer. |

```json
{"op": "add agent", "name": "reviewer", "content": "---\nname: reviewer\ndescription: Reviews code.\n---\n\nYou review code."}
{"op": "edit agent", "name": "reviewer", "document": "checklist.md", "content": "- Check the error paths."}
{"op": "remove agent", "name": "reviewer", "layer": "project"}
```

The fields:

- `name` is the id of the agent: the name of its folder. The names of the
  `name` field of `start agent` are also names of this field, for example
  `agent`.
- `content` is the full text of the file. For `add agent`, it is the whole
  `AGENT.md` with its frontmatter.
- `document` is the path of the file of `edit agent`, relative to the agent
  folder. With no `document`, the edit writes `AGENT.md`. A different path
  writes a resource of the agent, and the edit makes the folders of the
  path. The edit refuses an empty path, an absolute path, a path with a `..`
  component, and a path that goes out of the agent folder, also through a
  symbolic link.
- `layer` is `user` or `project`. With no `layer`, the write goes to the
  user layer. A different value gives a corrective that names the two layers
  and changes no file. The values are the values of the `layer` option of the
  `skills` tool.

``AgentWriteLayer`` gives the two layers. The target of a write is the
highest local layer of the registry with the source of the layer:

| `layer` | The target layer | The file of a new agent |
|---|---|---|
| `user` (the default) | The highest `.user` layer, for example the root settings folder of the host | `<user layer root>/<id>/AGENT.md` |
| `project` | The highest `.project` layer | `<project layer root>/<id>/AGENT.md` |

In ACPAgent, for example, the project layer is
`<working folder of the session>/.agents/`. When the registry has no local
layer of that source, the call gives the corrective "The '<layer>' layer is
not available here. Use a different layer." A `.defaults` layer and a
marketplace layer are read-only. A write never goes to them.

The rules of a write:

- The id must be valid: 1 to 64 characters of `a`-`z`, `0`-`9`, and `-`. It
  does not start or end with `-`, and it does not contain `--`.
- The ids `agents`, `skills`, `rules`, and `partials` are reserved. They are
  names of folders of the layer layout, and a write of such a folder damages
  other items of the layer. Each operation refuses them.
- `add agent` refuses an agent that exists in the target layer, in either
  form. The corrective tells the model to use `edit agent`. A copy of the
  same id in a lower layer is not an error: the new agent overrides it.
- `edit agent` and `remove agent` refuse an agent that does not exist in the
  target layer. The corrective names each local layer where the agent exists,
  thus the model can select the correct layer, or add an override.
- When the layer holds both forms of the agent, `<root>/<id>/` and
  `<root>/agents/<id>/`, `edit agent` writes the form that the catalog reads:
  `<root>/<id>/`.
- `remove agent` deletes both forms of the agent in its layer:
  `<root>/<id>/` and `<root>/agents/<id>/`. Thus no copy of that layer stays
  in the catalog. A copy in a different layer stays, and it can win the id
  after the reload.
- A refused write changes no file. Each refusal is a corrective answer that
  tells the model what to do next.

Each write and each delete is a coordinated access (`NSFileCoordinator`),
thus a sync service sees the change.

### The default agent

The agent `default` is the root `AGENT.md` of the layer, and its folder is
the layer root. `add agent` with the name `default` writes
`<layer root>/AGENT.md`, and `edit agent` changes it. `remove agent` refuses
it: the corrective tells the model to use `edit agent`. A document of the
agent `default` cannot go into the folder of a different item: the folder of
an agent, `agents/`, `_skills/`, `_rules/`, or `_partials/`.

### The answer and the change event

The answer starts with what the write did, for example
"Added the agent `reviewer` to the user layer: `/path/reviewer/AGENT.md`."
After a write of `AGENT.md`, the answer gives the diagnostics of the new
catalog for the agent. When the catalog does not hold the agent after the
reload, the answer says so first, with the diagnostics, thus the model can
correct the file with `edit agent`.

The reload gives one change event in the `changes(after:)` subscription of
the `agents` endpoint (see "The GraphQL endpoint" above): `add agent` puts
the id in `added`, `remove agent` puts it in `removed`, and an edit of the
winning `AGENT.md` puts it in `changed`. A write that does not change the
catalog content of the id gives no change event:

- An edit of a document that is not `AGENT.md`.
- An edit with the same text.
- An edit of a copy that a copy in a higher layer hides.

The answer compares the catalog before the write with the catalog after the
reload, with the same rule as the change log. Thus the answer says "The
catalog did not change." exactly when the reload gives no change event for
the id. When a copy in a different layer wins the id, the answer also names
that layer, for example "The catalog did not change: the copy in the project
layer wins."

## Scheduled agents

The tool also runs an agent on a timer. `schedule agent` takes a `schedule`
and a `prompt`, and optionally `agent` (the default agent when left out),
`until`, `count`, `title` and `timeZone`. The schedule is a 5-field cron
expression, one ISO date and time, or `every N minutes|hours|days`, read with
no model. English goes to the flash slot (the selection model of the
environment), whose answer must be one of these forms; an ambiguous text is
refused with a corrective, never guessed. The shortest schedule is 1 minute.
The answer shows the normalized schedule, the time zone, the next 3 firings
and the end. A recurring task with no `until` and no `count` ends after 7 days
(``AgentScheduledTask/defaultLifetime``).

`list schedules`, `get schedule`, `pause schedule`, `resume schedule`,
`start schedule` (`run schedule` by the verb alias: fire now) and
`cancel schedule` see only the tasks of the calling session.

Each firing is a child run of the session that made the task, started through
the runner as a restored child is: the caller is that session, on the mail
route. The result of every firing is mailed to that session, with the task
name, its id and the firing number. A firing that is due while the run of the
previous firing still works is skipped and counted. The firings that a sleep
or a down process missed run once, then the schedule goes on. A pending task
holds no work in its session; a running firing holds one `childSession` lease
in the work registry of its session.

A task belongs to its session: ``AgentRunner/cancelRuns(caller:)`` ends and
removes the tasks of the session. The host saves them with
``AgentRunner/useScheduleStore(_:)`` (an ``AgentScheduleStore`` over the
folder of each session), and a restart or a resume restores them with
``AgentRunner/restoreSchedules(of:workSite:)``.
