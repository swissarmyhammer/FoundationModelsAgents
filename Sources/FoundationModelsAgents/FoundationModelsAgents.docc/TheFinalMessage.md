# The final message

Read the result of a run that a model started with `start agent`.

## Overview

`start agent` is a background run.
In a Router session, the call waits for the run up to the settle period of
the session (`SessionConfiguration.inlineSettleGrace`). A run that ends in
that time gives its final message to the model as the answer of the call, and
no mail comes. A run that continues gives the pending envelope of the Router,
and works in the background. All its work is in its own transcript. The rest
of this article is about a run that continues.

### Messages before the final message

While the run works, it can send messages to its caller with `send caller`,
and the caller can send messages to it with `send agent` (see
<doc:DelegatingWithTheAgentsTool>). A message of the run comes to the
calling session as mail, in the same way as the final message. The Router
sends `SessionEvent.runMessage(_:)` for it, and the pump puts a line of this
form at the start of the next prompt of the calling session:

```
[agents] start agent (<token>) message, still running: <message>
```

The pump starts an answer to the message, and the run continues. A run that
started agents answers each message of a child before it ends. The answers to
messages count toward `mailOnlyAnswerLimit`, and the passes of these answers
count toward `maxTurns`. The run gives one final message when it ends, also
after it sent messages.

The body of the call waits for the run, and gives the final message text of
the run as the detail of the Router run. The Router makes the terminal of the
call: a `.completed` `OperationEvent` with that detail.
The final message comes to the calling session as mail.
The pump of the Router delivers the mail.
The pump puts the mail at the start of the next prompt of the calling session,
as a line of this form, and records it in the transcript of that session:

```
[agents] start agent (<token>) completed: <detail>
```

### The event

The event is always `.completed`, because only a `.completed` event is a
terminal that the Router delivers as mail. The `detail` is the text that
`check agent` gives for the run, thus it names the agent and the run:

| The run | `detail` | `outcome` |
|---|---|---|
| Finished | "Agent `name` (`id`) finished.", a blank line, and the full reply of its last answer. | `.succeeded` |
| Failed | "Agent `name` (`id`) failed: reason." | `.failed` |
| Cancelled | "Agent `name` (`id`) was cancelled." | `.cancelled` |

The name and the id in the `detail` let the model join each final message to
the run that it started. When two runs finish, the caller can tell which
result came from which. The full text stays in the `detail`, also when it is
longer than 4 096 characters. The Router records one terminal for each call.

### Act on the final message

The pump of the Router delivers mail only after the answer in operation ends.
Thus the pending envelope tells the model not to wait and not to guess the
result, but to end its answer. The pump then starts an answer to the mail
with no call of the host. The Router also sends
`SessionEvent.runSettled(event)` on `streamSessionEvents()`, and each answer
ends with `SessionEvent.answered(_:)`. An answer that answers only mail has no
message ids. A host reads these answers from its subscription:

```swift
let events = await root.streamSessionEvents()   // subscribe before the first message
_ = try await root.respond(to: userPrompt)
for await case .answered(let answer) in events where answer.messageIds.isEmpty {
    print(answer.reply)                          // the answer to a final message
}
```

A run that started agents uses the same path on its own session.
A run ends when its session is idle.
The session is idle when each run that it started ended, when the session
answered the final message and each message of each of those runs, when no
pending envelope waits for its final message, and when no message waits in
the queue. The
reply of the last answer is the result of the run.
The passes of each answer, also each answer to mail, count toward
`maxTurns`. When the Router holds the mail and starts no answer for it
(`SessionEvent.mailDeliveryPaused(_:)`), the run fails with
``AgentRunFailure/mailDeliveryPaused(_:)``.

### A run with no calling session

A host-driven run has no `ToolContext`, thus its final message goes to no
session. The host reads the result with ``AgentRun/result()``. When a model
calls `start agent` outside a Router session, no final message comes back,
and the model asks about the run with `check agent`.

### Close a calling session

The Router does not know these runs. Before the host closes a session that has
the `agents` tool, it calls ``AgentRunner/cancelRuns(caller:)`` with the id of
the session:

```swift
await runner.cancelRuns(caller: root.id)
await root.close()
```
