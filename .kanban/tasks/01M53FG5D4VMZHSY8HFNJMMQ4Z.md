---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m53jg6hk0tc84xkxj7wkvh6v
  text: |-
    ### done
    - `swift package update FoundationModelsExtras` in the package and in IntegrationTests: Extras 016c5a8 → 7a40759 (main). Package.resolved is in .gitignore, thus no file changes.
    - `swift build --build-tests`: no errors.
    - One full run (with the other cards of this check): 583 tests in 80 suites passed.
  timestamp: 2026-10-16T23:59:32.915632+00:00
position_column: done
position_ordinal: e880
title: Adopt Extras 7a40759 (main)
---
Move the Extras pin in Package.resolved from 016c5a8 to 7a40759 (main). Then build, and do one full test run.

- [ ] `swift package update FoundationModelsExtras`
- [ ] The build has no errors.
- [ ] One full run is green. #elicitation-check #waits-on-extras