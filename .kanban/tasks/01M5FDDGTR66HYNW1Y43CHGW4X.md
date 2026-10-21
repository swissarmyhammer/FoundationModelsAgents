---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5g28vb7gme539xwh1ca8kqr
  text: 'Research: `swift package update FoundationModelsExtras` resolved Extras main at 589f27e (contains 6716646; `git merge-base --is-ancestor 6716646 HEAD` true). Kit API: `GraphQLEndpointConformance.problems(of:scope:probes:codes:exceptions:clock:)`, clock is `any RunClock` (default ContinuousRunClock), limit `firstResponseLimit` = 10 s. `GraphQLConventions.changesField` is internal, so the test names "changes" itself. Conformance test is `AgentsGraphTests.theEndpointConforms`; hand-written alias test is `AgentsGraphChangesTests.aliasNamesTheChangesSubscription` (parameterized over agentChanges/agentsChanges, also checks since→after). Kit probe checks only one from→to rewrite per probe, so `agentsChanges` and `since` stay hand-written. Clock choice: pass `ContinuousRunClock()` explicitly, so a silent subscription fails after the 10 s limit instead of hanging (a never-advanced ManualRunClock would hang the test, against test rule T1); on success the first response comes at once from the ChangeLog buffer, so no real wait.'
  timestamp: 2026-10-21T20:26:02.471908+00:00
- actor: claude-code
  id: 01m5g2dztcwqmyndm45v6yrjzr
  text: |-
    ### implement — changed
    - evidence: Extras resolved at main 589f27e (has 6716646; Package.resolved is gitignored). 2 files — Tests/FoundationModelsAgentsTests/AgentsGraphTests.swift (theEndpointConforms now calls `problems(of:scope:probes:codes:exceptions:clock:)` with `agentNameProbe` and a `.subscription` probe `agentChanges`→`changes` built by the new `changesProbe(of:registry:layer:)`: read `cursor`, write `reviewer` into the TemporaryLayer.make(holdingAgent:) layer, `reload()`, subscribe `agentChanges(after: $after)`; clock `ContinuousRunClock()`), Tests/FoundationModelsAgentsTests/AgentsGraphChangesTests.swift (aliasNamesTheChangesSubscription keeps only `agentsChanges` + `since`, no longer parameterized). RED: before the catalog change existed, the kit reported "The subscription alias probe ... gave no response within 10.0 seconds." GREEN: theEndpointConforms passed in 0.026 s with `problems == []`. `swift test --filter AgentsGraph`: 36 tests in 4 suites passed, 0 failures. The only build warning is the SwiftPM build-system line "missing creator for mutated node: ('.../mlx-swift_Cmlx.bundle/Contents/MacOS')", from the mlx dependency bundle, not from source.
    - criteria: 1 and 2 checked; 3 (`swift test` full suite green) is left for the test step, since only the filtered run happened here.
    - next: /test for the full suite, then /review.
  timestamp: 2026-10-21T20:28:50.892381+00:00
- actor: claude-code
  id: 01m5g2f92d0xa4t9xer4ff0xfg
  text: |-
    ### test — green
    - evidence: `swift test` — 664 tests in 92 suites passed, 0 failed, 0 skipped. Only warning: SwiftPM "missing creator for mutated node" for the mlx-swift_Cmlx bundle (mlx dependency, out of scope).
    - next: review
  timestamp: 2026-10-21T20:29:33.133577+00:00
position_column: doing
position_ordinal: '80'
title: AgentsGraph conformance test probes the agentChanges subscription alias with the Extras kit
---
Optional cleanup after AG-8c (^20mv6d3). The conformance kit can now probe subscription aliases; this is on FoundationModelsExtras origin/main (code 6d5b7ba, b8a88c0; tip 6716646).

## What
- Adopt that Extras commit (`swift package update FoundationModelsExtras`).
- In the AgentsGraph conformance test, call `GraphQLEndpointConformance.problems(of:scope:probes:codes:exceptions:clock:)` with two probes:
  - the query probe `agent(name:)` → `agent(id:)`
  - `GraphQLAliasProbe(query:variables:from: "agentChanges", to: "changes", kind: .subscription)`
- The subscription probe needs an event at once: read `cursor`, make one catalog change (an agent folder in a `TemporaryLayer`, then `reload()`), and subscribe with `changes(after: <that cursor>)`. ExampleGraph's `changesProbe(writing:)` in the Extras tests shows the pattern.
- Use the injectable clock; the first response must arrive within 10 s.
- Remove the hand-written `agentChanges` part of `aliasNamesTheChangesSubscription`, if the kit now covers it. Keep `agentsChanges` and `since` there if the kit probes only one alias.

## Acceptance criteria
- [x] The conformance test checks the `agentChanges` alias through the kit, with no problems and no exceptions.
- [x] No duplicate hand-written test for the same alias.
- [x] `swift test` is green. #AG-8