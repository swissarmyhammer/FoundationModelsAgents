---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3fgjdrca6x6vvz4xjcdw5xa
  text: |-
    Research:
    - The old rule is in these places: plan.md §5 ("No `tools` key gives the full catalog." and "The `agents` tool is in the catalog under the name `agents`, so the same rules apply."), README.md (the `tools` bullet), RunningAnAgent.md step 3 ("when its keys permit it"), DelegatingWithTheAgentsTool.md ("when its `tools` key permits it").
    - Doc comments that state the old rule or a vague form of it: `AgentRunner.start` ("when its `tools` permit it"), `AgentRunner.catalog()` ("Each run of this runner gets the `agents` tool"), and the `start agent` operation in AgentsToolOperations.swift ("The new run gets an `agents` tool of its own").
    - ToolSelection.swift, ToolResolver.swift and LiveAgentFile.swift already state the new rule (^aypvkyx).
    - docs/skills-and-agents.md does not state the rule. Its "`list agents` gives the full catalog" row is about the agent catalog, not the tools; it stays.
    - Only DocumentationTests reads the DocC text. No test reads plan.md or the README prose. ReadmeExampleTests reads only the Swift blocks.
  timestamp: 2026-09-26T18:45:18.220671+00:00
- actor: claude-code
  id: 01m3fgv3td4de3rv7pywan3r4c
  text: |-
    Implementation notes:
    - RED seen first: 3 new claim rows of DocumentationTests failed for the expected reason (the articles did not state the rule).
    - What did not work: the first claim texts were one full sentence of about 100 characters. `theCatalogMakesEveryClaim` uses `text.contains` on the raw page, and a page wraps at 80 columns, so a long claim can not match. The claims are now two short sentences, and each one stands on one line of the page: "Only an explicit `tools` entry gives the `agents` tool." and "An agent with no `tools` key gets no `agents` tool." Both articles state both claims (4 claim rows).
    - The articles also name the entries (`Agent`, `Agent(a, b)`, `agents`) and state that `disallowedTools: Agent` removes the tool.
    - plan.md §1 and the README intro said "An agent can have this tool". Both now say that the `tools` key must list `Agent`.
    - Doc comments with the old or a vague form of the rule: `AgentRunner.start(_:prompt:)`, `AgentRunner.catalog()`, `StartAgent.execute(in:)`, `AgentRun.agentsTool(of:)`, and the `hasAgentsTool` parameter of `ToolResolver.diagnostics`.
    - docs/skills-and-agents.md needed no edit.
  timestamp: 2026-09-26T18:50:02.957668+00:00
- actor: claude-code
  id: 01m3fgv7ahhsrp02ajb9pybrvp
  text: |-
    ### implement — changed
    - evidence: 9 files — plan.md, README.md, Sources/FoundationModelsAgents/FoundationModelsAgents.docc/{RunningAnAgent,DelegatingWithTheAgentsTool}.md, Sources/FoundationModelsAgents/Run/{AgentRun,AgentRunner}.swift, Sources/FoundationModelsAgents/Tool/AgentsToolOperations.swift, Sources/FoundationModelsAgents/Tools/ToolResolver.swift, Tests/FoundationModelsAgentsTests/DocumentationTests.swift. `swift test --filter "DocumentationTests|ReadmeExampleTests|DocsTests"`: 19 tests in 3 suites pass. `swift build -Xswiftc -warnings-as-errors`: pass. `swift test -Xswiftc -warnings-as-errors`: 359 tests in 49 suites pass. `cd IntegrationTests && swift build --build-tests`: pass. swiftlint (Sources Tests Package.swift Examples): 0 violations.
    - next: /review. The task stays in doing.

    ```
    step: implement
    outcome: changed
    evidence: 9 files; doc tests 19/19 pass; swift test 359 tests in 49 suites pass; swiftlint 0 violations; IntegrationTests build pass
    task: ^v3stf0j
    ```
  timestamp: 2026-09-26T18:50:06.545693+00:00
depends_on:
- 01M3A6DF0468875FVSZAYPVKYX
- 01M3A6C3W4FTNNC249NNVFWH3M
position_column: doing
position_ordinal: '80'
title: 'Decision A (docs): the plan and the documents state the explicit Agent rule'
---
## What
After `^aypvkyx`, the documents must state the new rule: an agent gets the `agents` tool only through an explicit `Agent`, `Agent(a, b)`, or `agents` entry in `tools`. With no `tools` key it gets every other catalog tool.

- plan.md §5: rewrite "The `agents` tool is in the catalog under the name `agents`, so the same rules apply", and the "No `tools` key gives the full catalog" rule.
- `README.md` (the frontmatter key table), `docs/skills-and-agents.md` if it mentions it, and the DocC articles `RunningAnAgent.md` and `DelegatingWithTheAgentsTool.md`.

## Acceptance Criteria
- [x] plan.md §5, the README, and the DocC articles state the same rule, with no sentence that says a missing `tools` key gives the `agents` tool.

## Tests
- [x] Add the rule as a required claim in `Tests/FoundationModelsAgentsTests/DocumentationTests.swift` (the method it uses for design claims).
- [x] Run `swift test --filter "DocumentationTests|ReadmeExampleTests|DocsTests"`, then the full suite. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.