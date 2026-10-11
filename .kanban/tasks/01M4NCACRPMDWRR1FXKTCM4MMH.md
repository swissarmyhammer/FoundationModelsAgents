---
assignees:
- claude-code
position_column: done
position_ordinal: d180
title: Give the host an observer of the session events of each agent run
---
Request from the FoundationModelsACPAgent session (their task ^zbcrex8).

A shell run of an agent run uses the shell of the root session. The `toolInvocation` records of that run go only to the event stream of the agent run, and `AgentRun.follow` reads that stream in a private loop. Thus the host cannot see the completion tokens of the tool runs of an agent run before the tool output starts.

## Change
- Add `AgentEnvironment.RunEventObserver = @Sendable (AgentRun, SessionEvent) -> Void`.
- Add the optional `runEventObserver` parameter to `AgentEnvironment.make` (default `nil`). It is additive: current callers do not change.
- `AgentRun.follow` calls the observer synchronously, first, for each event, in stream order. Each run calls it, the child runs too.

## Contract (document it)
- The observer gets each event of the run in the order of the event stream.
- The Router yields the open record to the stream before the tool body starts. The follow loop calls the observer when it reads the record. The follow loop and the tool body are two tasks, thus the package cannot fully promise that the observer runs before the first output of the body. A strict promise needs a synchronous hook in the Router.
- The observer must return quickly: it holds the follow loop of the run.

## Tests
- A run whose tool body waits until the observer saw the open record of that tool run. The run finishes. The observer gets the open record before the close record, with the run id.
- With no observer, nothing changes (existing tests).