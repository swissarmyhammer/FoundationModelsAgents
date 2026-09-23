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
let skillsTool = try await SkillsTool.make(registry: skills)
var tools = ToolCatalog()
tools.register("skills") { skillsTool }

let env = AgentEnvironment(profile: profile, skills: skills,
                           workingDirectory: projectURL, tools: tools)
try await agents.load()
let runner = AgentRunner(registry: agents, environment: env)
```

The init of ``AgentRunner`` stores its inputs and does no I/O. The runner reads
the catalog of the registry at each start, thus call
``AgentRegistry/load()`` before the first run.

### Start a run and wait for it

``AgentRunner/start(_:prompt:)`` starts a host-driven run and gives the run at
once. ``AgentRun/result()`` waits for the run and gives the text of its last
turn.

```swift
let report = try await runner.start("code-reviewer", prompt: "Review:\n\(diff)").result()

async let review = runner.start("code-reviewer", prompt: p1).result()
async let tests = runner.start("test-writer", prompt: p2).result()
```

An unknown name throws ``AgentRunnerError/unknownAgent(name:available:)``.
`result()` throws the ``AgentRunFailure`` of a failed run, or
`CancellationError` for a cancelled run.

### What a run does

`start` does these steps before it returns:

1. It renders the body. Each `$ARGUMENTS` in the body becomes the prompt, as a
   quarantined span. Then the Stencil render runs on the body. A render
   failure fails the run with ``AgentRunFailure/bodyRenderFailed(_:)``.
2. It puts the instructions in order: the `AGENTS.md` files of the working
   directory, outermost first; the body; the body of each skill of the
   `skills:` key.
3. It resolves the tools. With no `tools` key, the run gets each tool of the
   ``ToolCatalog``. `disallowedTools` applies first, then `tools`. The run
   also gets its own `agents` tool when its keys permit it.
4. It matches the `model` key to a slot of the profile. An absent key or
   `inherit` gives the slot of the caller. For a host-started run, that is
   ``AgentEnvironment/defaultSlot``. `standard` and `flash` give that slot. A
   value with no match gives a warning, then `inherit`.
5. It makes the Router session.

Thus the run has its id when `start` returns. The run id is the session id,
and it is the name of the recording directory of the session. A run whose
setup fails has no session: it gets a new ULID, no recording directory, and
the state ``AgentRunState/failed(_:)``.

Then one turn runs in the background with the prompt as the first user
prompt. Nothing goes to the caller during the turn. When the turn ends, the
run closes its session. A finished run holds no session.

### The state of a run

``AgentRun/state`` is one of:

- ``AgentRunState/running``: the run is in operation.
- ``AgentRunState/finished(_:)``: the run gave its final text.
- ``AgentRunState/failed(_:)``: the run failed, with the reason.
- ``AgentRunState/cancelled``: the run was cancelled.

### The turn limit

The `maxTurns` key counts the passes of the control loop. In each pass the
model generates. Then it calls tools and the loop goes around again, or it
answers and the loop ends. One pass that calls three tools counts as one. The
run counts the passes over all its turns: the task turn and each delivery
turn. Above the limit, the run cancels its turn and fails with
``AgentRunFailure/hitMaxTurns(partial:)``, with the text so far.

### Cancel and stop

``AgentRun/cancel()`` cancels the turn of the run and the runs that it
started. The run waits for its children, closes its session, and goes to
``AgentRunState/cancelled``. ``AgentRunner/cancelRuns(caller:)`` cancels each
open run of one caller. ``AgentRunner/stop()`` cancels all the runs.

### The index

``AgentRunner/runs`` gives the runs in operation. ``AgentRunner/run(id:)``
gives a run in operation or the record of a finished run.
``AgentEnvironment/maxRetainedRuns`` limits the records, and the runner
removes the oldest record first.
