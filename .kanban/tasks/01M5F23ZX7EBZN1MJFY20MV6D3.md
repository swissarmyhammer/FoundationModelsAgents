---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5f3wprdg40ahr4mharejx84
  text: |-
    Unblocked: EXTRAS-10 is on FoundationModelsExtras origin/main (code f126153, tip 11ffe56). First step: `swift package update FoundationModelsExtras` and adopt that commit.

    API (Sources/FoundationModelsExtras/GraphQL/):
    - `actor ChangeLog<Event>`: `init(capacity: Int = 1024)`, `append(_:)`, `cursor`, `changes(after:where:)`. Stream elements are `ChangeLogEntry<Event> { cursor: String, at: Date, event }`. `changes(after: nil)` gives only live events.
    - IDChange.swift: use `ChangedIDs` (added/changed/removed ids) as the Event, and `IDChange` as the shared `<Noun>Change` shape (at as DateTime). Check how `IDChange` names its GraphQL type against the `AgentChange` name rule 9 wants.
    - Codes: `GraphQLToolkitError.notFound(kind:id:)` and `.resyncRequired(reason:)`.

    Behaviour to test:
    - A subscription stream that throws a coded error sends one final `{"errors":[…]}` with extensions.code, then ends normally.
    - A subscriber more than `capacity` events behind gets RESYNC_REQUIRED.

    EXTRAS-11 (conformance checks) has not landed; use the current GraphQLEndpointConformance until it does.
  timestamp: 2026-10-21T11:35:07.277045+00:00
depends_on:
- 01M5F23E7S4NJTPNFFVB8W613Y
position_column: todo
position_ordinal: '8280'
title: 'AG-8c AgentsGraph: changes(after:) subscription and opaque cursor from the ChangeLog'
---
## Blocked
Blocked on EXTRAS-10 (`ChangeLog<Event>` and the toolkit codes `NOT_FOUND`/`RESYNC_REQUIRED` in FoundationModelsExtras, features/packages/foundationmodels-extras.md, EXTRAS-9 rev 2, D115). EXTRAS-10 has no owner yet. Do not write a local seq/buffer: EXTRAS-9 rule 2 forbids a copy of a toolkit part. Start after Extras main has `ChangeLog`, and adopt that Extras commit first.

## What
EXTRAS-9 rule 9 (rev 2, D67) for the `agents` endpoint:
- `Subscription.changes(after: String): AgentChange!`. `AgentChange` has `cursor: String!`, `at: DateTime!`, `added: [ID!]!`, `changed: [ID!]!`, `removed: [ID!]!`. One event per reload. The client queries `agent(id:)` again for each added or changed id; a removed id needs no query, and there is no tombstone type.
- `Query.cursor: String!`: the opaque cursor of the catalog that a query reads. Query and cursor read one generation, so a client that reads `agents` then `changes(after: cursor)` misses no change.
- `ChangeLog` has an epoch per instance. A cursor from another epoch (for example, before a process restart), a cursor that is too old for the buffer, or a cursor after the newest event gives `RESYNC_REQUIRED`. No `after` starts from now.
- Feed: one `ChangeLog<AgentChange>` per `AgentRegistry` (rule 1: the endpoint and its ChangeLog are made once per port, not per `AgentsTool` copy, so every copy gives the same cursor). Feed it from `onReload` (the dotfolder watcher, `layerUpdates`, and an explicit `reload()`, so AG-9 writes also show). Diff consecutive catalogs by id and by the content of each definition (file content/modification, frontmatter, layer) into added/changed/removed. A reload with no difference appends nothing. A diagnostics-only change counts as `changed` for the agent it names.
- Use `ChangeLog.changes(after:where:)` only if a per-subscriber filter is needed (none is expected: the scope is the session folder and the host checks the folder).
- Alias tables: `agentChanges`, `agentsChanges` → `changes`; `since` → `after`.
- Remove the rule-9 exception from the conformance test of AG-8a.

## Acceptance criteria
- [ ] Adding, editing and removing `<name>/AGENT.md` in a watched layer each give one `AgentChange`, with that id in `added`, `changed` or `removed`, and a new cursor.
- [ ] One reload that changes several agents gives one event with all of their ids.
- [ ] `cursor` equals the cursor of the last event; `changes(after: cursor)` gives only later events.
- [ ] A cursor from another epoch, one that is too old, or one after the newest event gives `RESYNC_REQUIRED`.
- [ ] A reload with no difference gives no event.
- [ ] Two `AgentsTool` copies over one registry give the same cursor.

## Tests
- [ ] `GraphQLEndpointConformance.problems` is empty with no exception, with an alias probe for `agentChanges`.
- [ ] The schema golden is updated.
- [ ] Subscription tests over `TemporaryLayer` with explicit `reload()` (no wall-clock waits; each wait also ends on failure, test rule T1). #AG-8