# Loading the catalog

Make an agent registry over the layers, load it, and read its catalog.

## Overview

``AgentRegistry`` keeps the catalog of the agent folders. Its layers are, from
the lowest precedence to the highest:

```
marketplace[0] < … < marketplace[n] < defaults < user < agent folders < project
```

The local layers come from the `DotfolderStack` of the host. The marketplace
layers come from `MarketplaceLayerProviding.marketplaceLayers()`. A host that
wants `~/.claude` appends a local layer. The agent folders are an optional
input of the host (see "Agent folders" below). With no agent folder, the
layers are `marketplace[0] < … < marketplace[n] < defaults < user < project`.

An agent is a child folder of the `agents/` folder of a layer that holds
`AGENT.md`: `agents/<name>/AGENT.md`. The folder name is the id of the agent,
and the other files of the folder are the resources of the agent.
``AgentDefinition/folderURL`` gives the folder of the winning layer. The
highest layer that holds the `AGENT.md` of an id wins it, and each lower copy
gives an advisory. A local copy wins over a marketplace copy.

A `.md` file directly in `agents/` has the old format. It gives no agent. Each
such file gives one warning: "the file 'agents/<name>.md' has the old agent
format and does not load; move it to 'agents/<name>/AGENT.md'".

### Agent folders

An agent folder is a folder of agent folders. It has no `agents/` level and no
dot folder. The host gives the root of each one in `agentFolders:`, for example
a folder that a sync service keeps on each device of the user. The package
holds no code of a sync service: the host gives the URL.

```swift
let agents = AgentRegistry(stack: stack, agentFolders: [syncedAgentsFolder], watch: true)
```

```
<url>/
  AGENT.md                    the default agent, with the id `default`
  _partials/house-rules.md    the partials of the agents of this folder
  helper/AGENT.md             the agent `helper`
  helper/checklist.md         a resource of `helper`
```

- Each `<url>/<name>/AGENT.md` is one agent. The folder name is the id.
- `<url>/AGENT.md` is the default agent. Its id is always `default`
  (``AgentCatalog/defaultAgentID``), thus the precedence of the layers applies
  to it. Its `name` key is a display name, and the rule table does not compare
  it with the id. Each other rule applies. Its ``AgentDefinition/folderURL`` is
  `<url>`, and its resources are the files of `<url>` other than `AGENT.md`,
  `_partials/`, and the agent folders.
- ``AgentCatalog/defaultAgent`` gives the agent `default`, or `nil`. A host
  starts its root session from it when it is present, and uses its own
  instructions when it is `nil`.
- When `<url>/AGENT.md` and `<url>/default/AGENT.md` are in the same agent
  folder, the root file wins, and the subfolder gives one warning. A `default`
  agent in a higher layer, for example `agents/default/AGENT.md` of the
  project, wins over the root file, with the hidden-copy advisory.
- The agent folders are directly below the first `project` layer. Of two agent
  folders, the later URL wins, with the hidden-copy advisory.
- An include of `<url>/<name>/AGENT.md` walks from `<name>/_partials/` to
  `_partials/` of `<url>`. The default agent uses `_partials/` of `<url>`. An
  agent of an agent folder never reads a partial of a different layer, and an
  agent of a different layer never reads a partial of an agent folder. Each
  agent folder renders untrusted.
- A URL that does not exist, for example when the sync service is off, gives
  no agent and no diagnostic.
- The `description` rule is the same as for each other agent: an absent
  description is a warning, and the agent is not in
  ``AgentCatalog/modelVisible``. Thus a model can select only an agent with a
  description.
- A root run of an agent of an agent folder that names no working folder
  works in ``AgentDefinition/folderURL``. A slash-command run names the folder
  of the session that runs the command, thus it works in that folder. An agent
  of a dot folder never works in its own folder: that folder holds a
  definition in a configuration folder. See "The working folder of a run" in
  <doc:RunningAnAgent>.

A sync service can keep a file that is not local yet. Only the exact name
`AGENT.md` is an agent document. A conflict copy, for example `AGENT 2.md`, is
a resource and does not change the agent. Each of these gives one `skip`,
"the agent document is not local yet", with the URL of the file, and never
fails the catalog:

- A placeholder `.AGENT.md.<suffix>`, with a suffix that is not empty, in
  place of `<url>/AGENT.md` or `<url>/<name>/AGENT.md`.
- An `AGENT.md` that the build cannot read as text.

The host starts the download, and the next build loads the file. A sync
service keeps each folder and writes a placeholder only in place of a file.
Thus a different hidden file is a resource. For example, `.env.local` in `<url>`
gives no agent `env`, no diagnostic, and does not hide an agent `env` of a lower
layer.

The build reads each document of an agent folder in a coordinated read
(`NSFileCoordinator`), thus a sync service can give the current file. A
coordinated read that fails gives one `skip` with the cause of the failure:
"the coordinated read of the agent document failed", then the description of
the error.

### Make the registry, then load it

An init of ``AgentRegistry`` stores its inputs and reads no file. The registry
reads the files in ``AgentRegistry/load()`` and in ``AgentRegistry/reload()``.
Both are `async throws`. This design shows the I/O at the call site: a reader
of the code sees where the registry reads the files.

```swift
let agents = AgentRegistry(marketplaces: market, stack: stack,
                           variables: ["project": "acme"], watch: true)
await market.start()
try await agents.load()          // reads the files; after market.start()
let catalog = agents.catalog()   // no I/O
```

Call `load()` one time, after `market.start()`. Before the first `load()`,
``AgentRegistry/catalog()`` gives an empty catalog, and
``AgentRegistry/marketplaceLayers`` and ``AgentRegistry/layers`` are empty.
``AgentRegistry/isLoaded`` is `false` until the first `load()` or `reload()`
that does not throw.
`catalog()` does no I/O. It gives the catalog of the last build.

### Reload

Agent files change while the host runs. Thus ``AgentRegistry/reload()`` is a
normal path, and it does the same build as `load()` again. The registry also
reloads by itself:

- It follows each `layerUpdates` value of the marketplace provider.
- With `watch: true`, a `DotfolderWatcher` watches each local layer root, each
  agent-folder root, and each watchable marketplace layer root.

A change that a sync service makes from a different device is a file change in
the agent folder, thus the watcher sees it. When a placeholder becomes the full
`AGENT.md`, the sync service renames or writes a file in the folder, and the
watcher sees that too. A host that gets a change notification of its own, for
example from a metadata query, calls ``AgentRegistry/reload()``.

The build runs outside the lock, and the new catalog replaces the old catalog
in one step. A `catalog()` call during a reload gives the previous catalog. A
caller that holds a catalog keeps a value that does not change. A run in
operation keeps its definition.

``AgentRegistry/onReload`` publishes each new catalog, also the catalog of
`load()`. Each access to it is a new subscription, thus subscribe before the
change:

```swift
for await catalog in agents.onReload {
    let report = AgentReloadReport(catalog: catalog, marketplaceLayers: agents.marketplaceLayers)
    report.lines.forEach { line in log(line) }
}
```

### Read the catalog

``AgentCatalog`` gives:

- ``AgentCatalog/definitions``: each ``AgentDefinition``, sorted by id.
- ``AgentCatalog/diagnostics``: each ``AgentDiagnostic``, with its severity
  (`advisory`, `warning`, or `skip`), the agent name when it is known, and its
  provenance.
- ``AgentCatalog/listing``: one ``AgentListing`` for each definition.
- ``AgentCatalog/defaultAgent``: the agent `default`, or `nil`.
- ``AgentCatalog/modelVisible``: the agents that a model can start. An agent is
  model-visible when its description is valid and
  `disable-model-invocation` is not `true`.
- ``AgentCatalog/userInvocable``: the agents that are slash commands. An agent
  is user-invocable when `user-invocable` is not `false`.

A bad agent does not stop a good agent next to it. An `AGENT.md` with no
frontmatter, or an agent folder with a name that is not a valid id, is a skip.
A `name` that is not equal to the folder name, or an absent description, is a
warning.

The registry does not match the `model` key to a slot, because the registry has
no profile. ``AgentRunner/catalog()`` gives the catalog with the model warnings
and the tool warnings of each agent.
