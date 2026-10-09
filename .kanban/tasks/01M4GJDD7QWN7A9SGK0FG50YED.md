---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4gjk6arv9647kwbk3qp0fhc
  text: '2026-10-09: The user decided on the clean break. The swissarmyhammer/skills repo drops the Claude Code agent layout. On branch code-context, agents/general-purpose.md moved to agents/general-purpose/AGENT.md (not committed). That agent does not load until this Extras change is in. The plugin entry has no `agents` list, thus the resolver must read each folder in `<source>/agents/` that holds AGENT.md. Branch main still has eight agents/<name>.md files.'
  timestamp: 2026-10-09T14:55:36.792680+00:00
- actor: claude-code
  id: 01m4gjx5gpwx4nn68qmnx990yf
  text: '2026-10-09: The Extras session accepted the request. It is task ^wcm7ydh (01M4GJWM6FPGFHDTX1FWCM7YDH) on the FoundationModelsExtras board. Its /finish batch does it after ^1vhftw2 and ^jt7qx6k. Extras will tell foundationmodelsagents-3d and skills-79 when it is done.'
  timestamp: 2026-10-09T15:01:03.638769+00:00
position_column: todo
position_ordinal: '80'
title: 'Extras: scan-only marketplace with folder agents (agents/<name>/AGENT.md)'
---
## What

Track the Extras change that this package depends on. The request was sent to the Extras session (`foundationmodelsextras-ac`) on 2026-10-09. Do not edit the Extras repo from this session. Close this task when the Extras session reports that the change is in.

## User decisions (2026-10-09)

- A marketplace is a folder. The Marketplace module reads no catalog file (`marketplace.json`). It loads skills and agents only by a scan.
- An agent is a folder `agents/<name>/AGENT.md`. The folder name is the id. Other files are resources.
- Clean break: an old `agents/<id>.md` file gives one warning and does not load.

## Requested Extras changes

- Remove the catalog reads, plugin entries, `skills`/`agents` lists, renames and remote plugins from `CatalogResolver`.
- Scan: a SKILL.md folder is a skill, an AGENT.md folder is an agent. Do not scan into an entry folder. Skip `.git` and `node_modules`. Remove the depth limit of 3 so that `plugins/x/skills/y/SKILL.md` loads. A folder with both documents gives a warning. A name collision: the shallower wins, with a warning.
- `SkillSelection`: remove `.plugins(_:)`.
- `SnapshotWriter`: copy each agent folder to `<snapshot>/agents/<name>/`.

## Acceptance criteria

- [ ] The Extras session reports the change is in, with the commit.
- [ ] `Examples/agent-library/marketplace` in this package loads by the scan (update it in ^k542qak: remove `.claude-plugin/marketplace.json`).