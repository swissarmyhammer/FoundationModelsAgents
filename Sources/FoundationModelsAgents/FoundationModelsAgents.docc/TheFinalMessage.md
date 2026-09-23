# The final message

Read the result of a run that a model started with `start agent`.

## Overview

`start agent` returns at once, and it posts nothing. The call reads
`ToolContext.current` and gives it to the run. The runner maps the
`completionToken` of the call to the run. The run posts nothing while it
works. All its work is in its own transcript.

When the run ends, it posts one final message through that `ToolContext`: a
`.completed` `OperationEvent`. The Router journals the post into the
transcript of the calling session at once, and stages it. The next prompt of
the calling session reads it, as a line of this form:

```
[agents] start agent (<token>) completed: <detail>
```

### The event

The event is always `.completed`, because only a `.completed` event is a
terminal that makes the caller run a turn:

| The run | `detail` | `outcome` |
|---|---|---|
| Finished | The full text of its last turn. | `.succeeded` |
| Failed | "Agent `name` (`id`) failed: reason." | `.failed` |
| Cancelled | "Agent `name` (`id`) was cancelled." | `.cancelled` |

The run posts before the runner marks it finished, and it posts one time
only. The Router drops a second terminal for the same token.

### Act on the final message

Each journaled `.completed` post emits `SessionEvent.runSettled(event)`, into
the turn in operation or into `streamSessionEvents()`. A chat host waits for
the next user prompt. An autonomous host calls `dispatchNextPrompt()`, and the
Router runs one turn with the staged posts:

```swift
for try await event in root.streamEvents(to: userPrompt) {
    // .runSettled: an agent run has posted its final message
}
let followUp = try await root.dispatchNextPrompt()   // reads staged posts; nil when none
```

A run that started agents uses the same path. It does not finish while one of
its children is open. Each time a child ends, the run calls
`dispatchNextPrompt()` on its own session: this is a delivery turn. The passes
of each delivery turn count toward `maxTurns`.

### A run with no calling session

A host-driven run has no `ToolContext`, thus it posts nothing. The host reads
the result with ``AgentRun/result()``. When a model calls `start agent`
outside a Router session, no final message comes back, and the model asks
about the run with `check agent`.

### Close a calling session

The Router does not know these runs. Before the host closes a session that has
the `agents` tool, it calls ``AgentRunner/cancelRuns(caller:)`` with the id of
the session:

```swift
await runner.cancelRuns(caller: root.id)
await root.close()
```
