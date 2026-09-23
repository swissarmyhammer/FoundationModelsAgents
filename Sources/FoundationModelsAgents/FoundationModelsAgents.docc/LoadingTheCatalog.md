# Loading the catalog

Make an agent registry over the layers, load it, and read its catalog.

## Overview

``AgentRegistry`` keeps the catalog of the agent files. Its layers are, from
the lowest precedence to the highest:

```
marketplace[0] < … < marketplace[n] < defaults < user < project
```

The local layers come from the `DotfolderStack` of the host. The marketplace
layers come from `MarketplaceLayerProviding.marketplaceLayers()`. A host that
wants `~/.claude` appends a local layer.

The agent files are the `.md` files directly in the `agents/` folder of each
layer. The registry reads one level only. The file name is the id of the agent.
The highest layer wins a file name, and each lower copy gives an advisory. A
local copy wins over a marketplace copy.

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
`catalog()` does no I/O. It gives the catalog of the last build.

### Reload

Agent files change while the host runs. Thus ``AgentRegistry/reload()`` is a
normal path, and it does the same build as `load()` again. The registry also
reloads by itself:

- It follows each `layerUpdates` value of the marketplace provider.
- With `watch: true`, a `DotfolderWatcher` watches each local layer root and
  each watchable marketplace layer root.

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
- ``AgentCatalog/modelVisible``: the agents that a model can start. An agent is
  model-visible when its description is valid and
  `disable-model-invocation` is not `true`.
- ``AgentCatalog/userInvocable``: the agents that are slash commands. An agent
  is user-invocable when `user-invocable` is not `false`.

A bad file does not stop a good file next to it. A file with no frontmatter, or
with a file name that is not a valid id, is a skip. A `name` that is not equal
to the file name, or an absent description, is a warning.

The registry does not match the `model` key to a slot, because the registry has
no profile. ``AgentRunner/catalog()`` gives the catalog with the model warnings
and the tool warnings of each agent.
