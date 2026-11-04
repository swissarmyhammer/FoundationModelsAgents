---
comments:
- actor: claude-code
  id: 01m6kb6dvf87865zva22f5xj6j
  text: |-
    ### implement — changed
    - evidence: 6 files — Sources/FoundationModelsAgents/Run/AgentEnvironment.swift (transcriptReader, withTranscriptReader), Sources/FoundationModelsAgents/Run/AgentRun.swift (restore passes the reader), Sources/FoundationModelsAgents/FoundationModelsAgents.docc/RunningAnAgent.md, Tests/FoundationModelsAgentsTests/RestoredTranscriptReaderTests.swift, Tests/FoundationModelsAgentsTests/Support/TranscriptProbeTool.swift. RED: the new test failed to build (no withTranscriptReader). GREEN: 2 new tests pass. Full suite: 762 tests in 107 suites passed.
    - note: the Router checkout was old and had no transcriptReader argument on restoreSession. `swift package update FoundationModelsRouter` moved it to 6331c9c (Package.resolved is untracked). Router takes the reader as `transcriptReader:` of restoreSession. A live child keeps the reader through childSite of the parent call.
    - next: review. Nothing is committed or pushed.
  timestamp: 2026-11-04T13:15:25.423253+00:00
position_column: doing
position_ordinal: '80'
title: Give the transcript reader to a restored child session (AgentRun.restore)
---
AgentRun.restore (Sources/FoundationModelsAgents/Run/AgentRun.swift) calls restoreSession without transcriptReader, so a child session that a cold resume restores has no SessionTranscriptReader, and a tool in it gets SessionTranscriptError.noSource. A live child keeps the reader of its parent (Router childSite). Needed: AgentEnvironment carries an optional transcriptReader, and restore gives it to restoreSession. Then the ACP agent (FoundationModelsACPAgent, card ^zgqxj7z) gives it in AgentsComposition and adds the test for the restore of a child session. Found by the review of ^zgqxj7z. Not changed by the ACP agent, because the package is a family package.