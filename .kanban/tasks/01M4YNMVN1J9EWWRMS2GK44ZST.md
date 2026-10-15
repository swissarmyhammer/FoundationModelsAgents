---
assignees:
- claude-code
position_column: done
position_ordinal: dc80
title: 'Adopt Router 77b2da68 and Extras 278e9cb: the three new SessionEvent cases'
---
Move the Router pin to 77b2da68 and the Extras pin to 278e9cb. Add .workStarted, .workEnded and .elicitationEnded to each exhaustive switch on SessionEvent, with no default and no behavior change. agents-demo writes no line for them. Build, run the full suite one time, build IntegrationTests, commit, and push when green. #mail-new-events