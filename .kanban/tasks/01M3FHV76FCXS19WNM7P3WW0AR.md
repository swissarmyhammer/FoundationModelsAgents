---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3n654c7qqhsy3g9a3jppc37
  text: |-
    Research and change:
    - The claim of the card is correct. `AgentsToolDescription.delegationSentence` said "call this tool with {...}" and did not name the tool.
    - The Router records no `.toolCalls` entry for a rejected call. It sends the prompt again with the tool error "Tool error: Your call to the tool "x" was rejected (undeclared_tool), and no tool ran." The transcript records that `.prompt` entry. `ToolCallPayload` is internal to the Router, thus the live test reads the prompt text to find a rejection.
    - New sentence: 'To give a task to an agent, call the tool "agents" with the arguments {"op": "start agent", "name": "<name>", "prompt": "<the full task>"}. The value of "op" is an operation of the tool "agents", not the name of a tool.' The tool name comes from `ToolVocabulary.agentsToolName`.
    - The check sentence, the list forms, and the pinned schema did not change. The `list agents` answer ends with the new sentence, because it uses `delegationSentence`.
    - plan.md §9.1 quotes the new text. The DocC article does not quote the fixed sentences, thus it did not change.
    - FullCircleTests: both cases now expect no rejected tool call in the root transcript (`LiveRecording.rejectedToolCallPrompts(in:)`).
  timestamp: 2026-09-28T23:38:43.463766+00:00
- actor: claude-code
  id: 01m3n82tknmt39e7dcag89zczq
  text: |-
    ### implement — changed
    - evidence: 5 files — Sources/FoundationModelsAgents/Tool/AgentsToolDescription.swift, Tests/FoundationModelsAgentsTests/AgentsToolDescriptionTests.swift, IntegrationTests/Tests/AgentsIntegrationTests/FullCircleTests.swift, IntegrationTests/Tests/AgentsIntegrationTests/Support/LiveRecording.swift, plan.md. RED: 14 issues in "Agents tool description" before the source change. `swift test -Xswiftc -warnings-as-errors`: 390 tests in 56 suites passed. `swiftlint lint Sources Tests Package.swift Examples`: 0 violations in 134 files. `cd IntegrationTests && swift build --build-tests -Xswiftc -warnings-as-errors`: build complete. `cd IntegrationTests && swift test`: 3 runs in a row, each 12 tests in 6 suites passed, with the new expectation of no rejected tool call in the root transcript. An old recording from before the change (01M3FRHP5G7GF7M7X3KF8HWQY7) holds 'Tool error: Your call to the tool "start agent" was rejected (undeclared_tool)' on a `.prompt` entry, thus the new expectation finds this failure. The recordings of the new runs hold no such text.
    - next: /review
  timestamp: 2026-09-29T00:12:25.077849+00:00
- actor: claude-code
  id: 01m3n88q80abkpzndnwprka9km
  text: |-
    ### test — green
    - evidence: `swift build -Xswiftc -warnings-as-errors` clean (Build complete); `swift test -Xswiftc -warnings-as-errors` — 390 tests, 56 suites, all passed, 0 failed, 0 skipped; `swiftlint lint Sources Tests Package.swift Examples` — 0 violations, 0 serious, in 134 files; `cd IntegrationTests && swift build --build-tests -Xswiftc -warnings-as-errors` clean (Build complete)
    - next: ready for review
  timestamp: 2026-09-29T00:15:38.240195+00:00
- actor: claude-code
  id: 01m3n8d3abs2zg5s8vgt9mbdr3
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (3df229c): 0 findings (0 confirmed, 0 refuted; 7 attempted, 0 failed). The .kanban files are not reviewed (.reviewignore). plan.md is not reviewed (no validator matches). There are no prior review findings. All acceptance criteria are checked.
    - next: none. The task is in done.
  timestamp: 2026-09-29T00:18:01.675220+00:00
- actor: claude-code
  id: 01m3n8dc71q98f8wata9612vqn
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 5 files (AgentsToolDescription.swift, AgentsToolDescriptionTests.swift, FullCircleTests.swift, LiveRecording.swift, plan.md); live suite passed 3 runs in a row
    - test: green — swift test -Xswiftc -warnings-as-errors, 390 tests in 56 suites passed; swiftlint 0; IntegrationTests build-tests complete
    - commit: 3df229c
    - review: clean — 0 findings
  timestamp: 2026-09-29T00:18:10.785372+00:00
depends_on:
- 01M3A6EGTPK2A08N066GGPYAEM
- 01M3FMWXRW3637CJ74T7F7Z6QA
position_column: done
position_ordinal: bb80
title: 'The agents tool description: a model calls the op name "start agent" as a tool'
---
## What
In the live test `FullCircleTests` "The root starts the sub-agent from the tool description, with no JSON in the prompt" (task ^3h1kbyf), the `standard` root model first calls a tool with the name "start agent". That is the op name, not the tool name. The Router rejects the call with `undeclared_tool`. Then the model calls the `agents` tool correctly, and the test passes.

The fixed sentences in `Sources/FoundationModelsAgents/Tool/AgentsToolDescription.swift` say: `To give a task to an agent, call this tool with {"op": "start agent", ...}`. They do not name the tool `agents`.

## Change
- Find a text for `AgentsToolDescription.delegationSentence` that makes a small model call the `agents` tool on the first try. Examples to try: name the tool (`call the tool "agents" with ...`), or say that `op` is an argument.
- Keep the pinned schema and the other description forms.

## Acceptance Criteria
- [x] In the root transcript of the no-JSON live case, the first tool call of the root is a call of `agents`, with no `undeclared_tool` error, in 3 runs in a row.
- [x] The unit tests of the description text are updated.

## Tests
- [x] The unit tests of `AgentsToolDescription`.
- [x] Run `cd IntegrationTests && swift test` 3 times. Expected: pass each time.