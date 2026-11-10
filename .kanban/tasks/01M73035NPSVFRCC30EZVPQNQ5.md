---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m737xq7tjcdeagr862hnj91w
  text: |-
    Research and implementation notes:
    - CI does not run DocC: ci.yml gives no `docc-target` input to the shared workflow, and Package.swift has no swift-docc-plugin, thus `swift package generate-documentation` is not available. The DocC check is the method of the earlier documentation task: `swift package dump-symbol-graph --minimum-access-level public`, then `xcrun docc convert <catalog> --additional-symbol-graph-dir <dir with FoundationModelsAgents*.symbols.json> --warnings-as-errors`.
    - On main, that build gave 29 errors before this task: symbol links in public doc comments and in RunningAnAgent.md to internal or external symbols (AgentsToolText, Mail, SessionOutput, RouterSessionDirectory, OperationOutcome, and others), the old signature `restore(_:prompt:deferStart:claiming:)` (now with `caller:`), `restoreInterrupted(of:caller:directory:)` (now with `prompts:`), `select(children:statuses:)` (the real one is `select(children:)`), `AgentRunMessageOutcome/delivered` (now `delivered(_:)`), a missing `caller` parameter doc of `AgentRunner.restore`, and a double-backtick example sentence in DelegatingWithTheAgentsTool.md. The acceptance criterion needs a build with no warning, thus I changed each such link to a code span or to the correct symbol, and documented `caller`. Only doc comments changed in the Swift sources.
    - The real behavior that the docs state: `add agent` of `default` writes the root AGENT.md (it is not edit only: add works when the layer has no root AGENT.md); `remove agent` of `default` gives `cannotRemoveDefault`. `create`/`new` map to add through the default aliases of the resolver. A skipped add (no frontmatter) gives a diagnostic of the id, thus it DOES give a change event; the no-event cases are only the three that the tests show: an edit of a document that is not AGENT.md, an edit with the same text, an edit of a copy that a higher layer hides.
    - DocumentationTests: `toolOperations` now holds add/edit/remove agent. RED: 3 issues on DelegatingWithTheAgentsTool before the doc change.
  timestamp: 2026-11-10T17:26:05.306195+00:00
- actor: claude-code
  id: 01m737xt8whmxnndrfnpwnws5z
  text: |-
    ### implement — changed
    - evidence: 14 files — DelegatingWithTheAgentsTool.md (new section "Writing agents", table rows, verb aliases, mount list, child-run note), LoadingTheCatalog.md, FoundationModelsAgents.md (AgentWriteLayer in topics), RunningAnAgent.md, README.md, docs/skills-and-agents.md, DocumentationTests.swift, and doc comments only in AgentsGraph.swift, AgentEnvironment.swift, AgentRun.swift, AgentRunRestore.swift, AgentRunRestore+Interrupted.swift, AgentRunner.swift, AgentsTool.swift. `xcrun docc convert ... --warnings-as-errors`: exit 0, 0 diagnostics (29 errors on main before). `swift test`: 913 tests in 119 suites passed, 0 failures, no warning in our code.
    - next: /review
  timestamp: 2026-11-10T17:26:08.412090+00:00
- actor: claude-code
  id: 01m7382gm1945dmdreqtwd7acy
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (d87a59b): 0 findings, 0 confirmed, 0 refuted. No validator matches the 6 Markdown files of this change (README.md, docs/skills-and-agents.md, and 4 files in FoundationModelsAgents.docc). The engine did not review these files. The .reviewignore rule excludes the 2 .kanban files.
    - next: none. The task is in done.
  timestamp: 2026-11-10T17:28:42.369053+00:00
- actor: claude-code
  id: 01m7384htzgv411a2bf570tv0t
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — DelegatingWithTheAgentsTool.md, LoadingTheCatalog.md, FoundationModelsAgents.md, RunningAnAgent.md, README.md, docs/skills-and-agents.md, DocumentationTests.swift; doc comments only in 7 Swift files
    - test: green — swift build --build-tests 0 warnings in our code; swift test 913 passed in 119 suites (ReadmeExampleTests is in it)
    - docc: xcrun docc convert --warnings-as-errors exit 0, 0 diagnostics (checked again by the orchestrator)
    - commit: d87a59b
    - review: clean — 0 findings; the 6 Markdown files have no validator, so the engine did not read them
  timestamp: 2026-11-10T17:29:49.151296+00:00
depends_on:
- 01M7302JRZ9TWN09M5V08FZTZN
position_column: done
position_ordinal: ff8e80
title: 'AG-9: document the write operations of the agents tool'
---
## What
Write the documents for `add agent`, `edit agent`, `remove agent` and the `layer` option (D87, D175). Use Simplified Technical English.

- `Sources/FoundationModelsAgents/FoundationModelsAgents.docc/DelegatingWithTheAgentsTool.md`: a new section "Writing agents". It gives the three operations, the fields `name`, `content`, `document` and `layer`, the default `user`, the target folder of each layer (`<user layer root>/<id>/AGENT.md`, `<project layer root>/<id>/AGENT.md`; the project layer is the `.project` layer of the registry, in ACPAgent `<cwd of the session>/.agents/`), the reserved ids, the rule that `remove agent` deletes both forms of the agent in its layer, the cases that give no change event, the default agent (`default` is the root `AGENT.md`, edit only), the reload and the change event of the `agents` endpoint, and the rule that a defaults or marketplace layer is read-only.
- `Sources/FoundationModelsAgents/FoundationModelsAgents.docc/LoadingTheCatalog.md`: one paragraph that says the tool writes into the user and project layers, and the registry reloads after each write.
- `Sources/FoundationModelsAgents/FoundationModelsAgents.docc/FoundationModelsAgents.md`: add `AgentWriteLayer` to the topics.
- `README.md` and `docs/skills-and-agents.md`: add the three operations to each list of the operations of the `agents` tool.

## Acceptance Criteria
- [ ] Each document that lists the operations of the `agents` tool names `add agent`, `edit agent` and `remove agent`.
- [ ] The DocC catalog builds with no warning.

## Tests
- [ ] `swift package generate-documentation --target FoundationModelsAgents --warnings-as-errors` (or the DocC command that CI uses, see `Tests/FoundationModelsAgentsTests/CIWorkflowTests.swift`) passes.
- [ ] `swift test --filter ReadmeExampleTests` passes.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #step1 #AG-9