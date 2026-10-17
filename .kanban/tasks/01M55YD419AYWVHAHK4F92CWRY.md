---
assignees:
- claude-code
position_column: done
position_ordinal: ec80
title: 'LiveSourcesTests: a failed sync of the skills marketplace fails with its cause'
---
CI 38984256105 attempt 3 failed at LiveSourcesTests.swift:94 with "The folder “agents” doesn't exist". The cause was a network fault to github.com: remote_head did not complete, so the store had no snapshot.

- [ ] Before the folder read, `#require` that the store has a snapshot for the skills marketplace.
- [ ] The message of the `#require` gives the sync state or the error.
- [ ] Do not add a clock or a time limit. #integration-tests