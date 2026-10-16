# Running an agent

Start a run of an agent from the host, wait for its final text, or cancel it.

## Overview

One ``AgentRun`` is one delegated task: one agent, one prompt, and one Router
session. ``AgentRunner`` is the actor that owns each run of one host. It
starts the runs, keeps the index of the runs, and keeps the records of the
finished runs.

### Make the environment and the runner

``AgentEnvironment`` holds the dependencies and the limits of the runs: the
resolved `LanguageModelProfile`, the `SkillsRegistry`, the working directory,
the ``ToolCatalog``, the default slot, ``AgentEnvironment/maxConcurrentAgents``,
``AgentEnvironment/maxDepth``, and ``AgentEnvironment/maxRetainedRuns``.

```swift
let env = try await AgentEnvironment.make(profile: profile, skills: skills,
                                          workingDirectory: projectURL, tools: tools)
try await agents.load()
let runner = AgentRunner(registry: agents, environment: env)
```

The `SkillsRegistry` is the one source of the skills.
``AgentEnvironment/make(profile:skills:skillsSelectionModel:skillsCatalogCharacterLimit:skillsVisibility:workingDirectory:tools:defaultSlot:maxConcurrentAgents:maxDepth:maxRetainedRuns:budget:tracer:logger:metricsFactory:inlineSettleGrace:runEventObserver:)``
makes the `skills` tool from it, and adds the tool to the ``ToolCatalog``
under the name `skills`. The `skills:` preload of each run reads the same
registry, with the visibility rule of the tool. Give
``AgentEnvironment/skillsTool`` to the root session of the host, thus the
host and the runs read one registry. A `skills` entry in the tool catalog of
the host is a programmer error, and it stops the process.

The init of ``AgentRunner`` stores its inputs and does no I/O. The runner reads
the catalog of the registry at each start, thus call
``AgentRegistry/load()`` before the first run. Before that call,
``AgentRunner/start(_:prompt:)`` and
``AgentsTool/make(context:catalogCharacterLimit:)`` throw
``AgentRunnerError/catalogNotLoaded``.

### Start a run and wait for it

``AgentRunner/start(_:prompt:)`` starts a host-driven run and gives the run at
once. ``AgentRun/result()`` waits for the run and gives the reply of its last
answer.

```swift
let report = try await runner.start("code-reviewer", prompt: "Review:\n\(diff)").result()

async let review = runner.start("code-reviewer", prompt: p1).result()
async let tests = runner.start("test-writer", prompt: p2).result()
```

An unknown name throws ``AgentRunnerError/unknownAgent(name:available:)``.
`result()` throws the ``AgentRunFailure`` of a failed run, or
`CancellationError` for a cancelled run.

### The working folder of a run

Each run has one working folder. The session of the run gets it, and the
`AGENTS.md` documents of the instructions come from it.
``AgentRunner/start(_:prompt:workingDirectory:)`` gives the folder of a
host-driven run:

```swift
let report = try await runner.start("code-reviewer", prompt: task, workingDirectory: repoURL).result()
```

The folder of a run is the first of these:

1. The folder of the start request: the `workingDirectory` argument of
   ``AgentRunner/start(_:prompt:workingDirectory:)``, or the
   `workingDirectory` field of `start agent`. A relative path of
   `start agent` starts from the folder of the calling run. A slash command
   of the runner is a request from the session that runs it: its folder is
   the `workingDirectory` of the `SlashCommand.Invocation`, the folder of
   that session. Thus a command run of an agent of an agent folder also works
   in the folder of the session, not in its own folder.
2. For a child run, the folder of the parent run. A parent that gives a task
   expects the child to work on the files of the parent.
3. Only for an agent of an agent folder (`agentFolders` of the registry), the
   folder of the agent: ``AgentDefinition/folderURL``.
4. ``AgentEnvironment/workingDirectory``.

An agent of the dot-folder stack (`agents/<id>/` of a marketplace, defaults,
user, or project layer) never works in its own folder: that folder holds a
definition in a configuration folder. ``AgentRunner/start(_:prompt:)`` names
no folder.

### What a run does

`start` does these steps before it returns:

1. It renders the body. Each `$ARGUMENTS` in the body becomes the prompt, as a
   quarantined span. Then the Stencil render runs on the body. A render
   failure fails the run with ``AgentRunFailure/bodyRenderFailed(_:)``.
2. It puts the instructions in order: the `AGENTS.md` files of the working
   folder of the run, outermost first; the body; the body of each skill of the
   `skills:` key.
3. It resolves the tools. `disallowedTools` applies first, then `tools`. With
   no `tools` key, the run gets each tool of the ``ToolCatalog``.
   An agent with no `tools` key gets only the message operations, and only in a run with a caller.
   Only an explicit `tools` entry gives the operations that start agents.
   The entries are `Agent`, `Agent(a, b)`, and `agents`. A run with one of
   these entries, and with a depth less than ``AgentEnvironment/maxDepth``,
   gets its own instance of the tool with each operation. A run with a caller
   and no such tool gets a tool with only `send agent` and `send caller`.
   `disallowedTools: Agent` removes the tool (see
   <doc:DelegatingWithTheAgentsTool>).
4. It matches the `model` key to a slot of the profile. An absent key or
   `inherit` gives the slot of the caller. For a host-started run, that is
   ``AgentEnvironment/defaultSlot``. `standard` and `flash` give that slot. A
   value with no match gives a warning, then `inherit`.
5. It makes the Router session.

Thus the run has its id when `start` returns. The run id is the session id,
and it is the name of the recording directory of the session. A run whose
setup fails has no session: it gets a new ULID, no recording directory, and
the state ``AgentRunState/failed(_:)``.

Then the run mails the prompt as the first mail of its session, and the
session answers it in the background. A run with a caller can send messages
to that caller with `send caller` while it works. A caller can send messages
to the run with `send agent`, and a host calls ``AgentRun/deliver(_:from:)``
for a run that it started. A session sends with `MailSender.session(_:)`, and
the run mails an agent message: the prompt holds the line
"[message from session <id>]" and the message. A host that is not a session
sends with `MailSender.user`, and the prompt holds
``AgentsToolText/callerMessage(_:)``. Each other sender throws
``AgentRunMessageError/unsupportedSender(_:)``. The run holds a message that
comes before the task prompt is in the mail queue, and mails it at once after
the task prompt. After that time the mail queue is first in, first out, thus
the session gets each message after the task prompt. The run answers each
message that it accepted before it ends. A
run that started no agents and got no message ends when this answer ends,
and the reply of this answer is its result.

A run that started agents waits for them. `start agent` is a background run
of the Router, thus the final message of each agent comes to the session of
the run as mail. Each message that an agent sends with `send caller` also
comes as mail. The pump of the Router delivers the mail and starts an answer
to it, with no call of the run. An answer to mail can start more agents.

A run ends when its session is idle.
The session is idle when each agent that the run started ended, when no tool
call of the session is open, when each mail of those agents and each message
to the run has a terminal event, and when no message waits in the queue. A
terminal event is the answer of the mail, its failed answer, its cancel, or
its loss. The rule goes by mail id, and it reads no text of a prompt. When the
answer of a message from the caller fails, the run fails with the failure of
that answer, also after the answer of its task prompt.
The reply of the last answer is the result of the run. When the Router holds
the mail and starts no answer for it, the run pauses: it does not stop the
runs that it started, and ``AgentRun/pause`` tells the hold and the count of
runs that it waits for. When each of them ended, the run fails with
``AgentRunFailure/mailDeliveryPaused(_:)`` and the held results. A message
from the caller (``AgentRun/deliver(_:from:)``) ends the hold, and the run
goes on.

When the run ends, it closes its session. A finished run holds no session.

### The state of a run

``AgentRun/state`` is one of:

- ``AgentRunState/running``: the run is in operation.
- ``AgentRunState/finished(_:)``: the run gave its final text.
- ``AgentRunState/failed(_:)``: the run failed, with the reason.
- ``AgentRunState/cancelled``: the run was cancelled.

### Observe the events of each run

Give ``AgentEnvironment/runEventObserver`` to see the session events of each
run, the child runs too. The observer gets the run and the session output:
the event and its origin (the ids of the mail or the signal that started
it). For example, the open `toolInvocation` record of a tool run of a run
carries the completion token of that tool run.

```swift
let env = try await AgentEnvironment.make(
    profile: profile, skills: skills, tools: tools,
    runEventObserver: { run, output in
        if case .toolInvocation(let record, _) = output.event, record.closedAt == nil {
            joins.add(run: run.id, token: record.correlationID)
        }
    })
```

The run calls the observer synchronously in the loop that reads its
events, before the run uses the event. Thus the observer gets the events of
one run in their order. It holds that loop, thus it must return quickly.
The Router gives the open record before the body of the tool starts, but
the loop and the body are two tasks. Thus the observer gets the open record
while the body runs at the latest. The package does not promise that the
observer runs before the first output of the body.

### The turn limit

The `maxTurns` key counts the passes of the control loop. In each pass the
model generates. Then it calls tools and the loop goes around again, or it
answers and the loop ends. One pass that calls three tools counts as one. The
run counts the passes from the live events of its session, over all its
answers: the answer to the task prompt and each answer to mail. Above the
limit, the run stops its session and fails with
``AgentRunFailure/hitMaxTurns(partial:)``, with the text so far.

### Cancel and stop

``AgentRun/cancel()`` cancels the answer of the run and the runs that it
started. The run waits for its children, closes its session, and goes to
``AgentRunState/cancelled``. ``AgentRunner/cancelRuns(caller:)`` cancels each
open run of one caller. ``AgentRunner/stop()`` cancels all the runs. Both calls
also wait for each start of the target whose setup is in operation, then
cancel that run. After ``AgentRunner/stop()``, ``AgentRunner/start(_:prompt:)``
throws ``AgentRunnerError/stopped``.

### The index

``AgentRunner/runs`` gives the runs in operation. ``AgentRunner/run(id:)``
gives a run in operation or the record of a finished run.
``AgentEnvironment/maxRetainedRuns`` limits the records, and the runner
removes the oldest record first.
