---
assignees:
- claude-code
position_column: todo
position_ordinal: '8e80'
title: 'The agents tool description: a model calls the op name "start agent" as a tool'
---
## What
In the live test `FullCircleTests` "The root starts the sub-agent from the tool description, with no JSON in the prompt" (task ^3h1kbyf), the `standard` root model first calls a tool with the name "start agent". That is the op name, not the tool name. The Router rejects the call with `undeclared_tool`. Then the model calls the `agents` tool correctly, and the test passes.

The fixed sentences in `Sources/FoundationModelsAgents/Tool/AgentsToolDescription.swift` say: `To give a task to an agent, call this tool with {"op": "start agent", ...}`. They do not name the tool `agents`.

## Change
- Find a text for `AgentsToolDescription.delegationSentence` that makes a small model call the `agents` tool on the first try. Examples to try: name the tool (`call the tool "agents" with ...`), or say that `op` is an argument.
- Keep the pinned schema and the other description forms.

## Acceptance Criteria
- [ ] In the root transcript of the no-JSON live case, the first tool call of the root is a call of `agents`, with no `undeclared_tool` error, in 3 runs in a row.
- [ ] The unit tests of the description text are updated.

## Tests
- [ ] The unit tests of `AgentsToolDescription`.
- [ ] Run `cd IntegrationTests && swift test` 3 times. Expected: pass each time.