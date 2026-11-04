# 23. The graph view

People see a Yantra program as a graph: nodes and the links between them, each node with
its settings. They change it by changing settings, adding nodes and connecting them. They
can export it as JSON. The code under it stays in the Atlas, seen by the model and by
the developers a space trusts. (This book is internal: publicly, Yantra programs are node
graphs; see the positioning note.)

The graph is not a picture made for show. It is computed from what the Atlas already
holds: every program is cells, and the Atlas already knows which cell uses which.

## 23.1 Nodes

| Node | What it is | From |
|---|---|---|
| Record | data, with its fields and rules | a `record` cell (**built**) |
| View | a screen | a `view` cell (**built**) |
| Function | a step of logic | a `proc` or `func` cell (**built**) |
| Tool | something a person runs | a `tool` cell (**built**) |
| Schedule | work on a clock | an `every` cell (**built**) |
| Flow | work that lasts, step by step | a `flow` cell (**planned**, §3) |
| Lens | a site: a choice, a ranking, a view | a `lens` cell (**planned**, §22) |
| Agent | an agent and its charter | a `charter` (**planned**, §19) |
| Model | a provider the studio calls | a `Provider` row (**planned**, §12) |
| Extension | a package of all of these | **planned**, §0 |

The Atlas already gives each cell its kind from its code (**built**: atlas tests, "cell
kinds come from the code").

## 23.2 Links

| Link | Meaning | From |
|---|---|---|
| uses | this node calls or reads that one | `atlas.ref` (**built**) |
| points to | a record's field links to another record | link fields (**built**) |
| shows | a view reads a record | the view's queries (**built** at compile time) |
| feeds | one flow step hands work to the next | `flow` (**planned**) |
| calls | a node calls a model | studio calls (**planned**) |
| may | a grant lets a node or agent act | grants (**planned**, §0.4) |

## 23.3 Zoom

- **A space:** its apps, extensions and agents.
- **An app:** its records, views, functions, flows and lenses, and how they connect.
- **A node:** its settings and its ports. Inside a flow, a studio pipeline or a charter,
  its steps are a graph of their own. Inside a function, the view shows its settings and
  what it connects to; its code is not drawn as boxes.

## 23.4 Changing a program through the graph

- **Settings** are a node's `param`s. A GUI changes one, and the Atlas writes the new value
  into the code as a new version of the cell, its range and comment kept (**built**: `param`,
  `setParam`, `tuneParam`, t_views).
- **Adding a node** makes a cell from a template, with the settings filled in. **planned**
- **Connecting two nodes** sets a link field or a use. **planned**
- **Every change is a new version of a cell**, so undo is the cell's history (**built**).

## 23.5 JSON export

```json
{
  "yantra": "graph/1",
  "space": "@asha-store",
  "nodes": [
    {"id": "orders.Order", "kind": "record", "name": "Order",
     "settings": {"keep history": "7 years"},
     "ports": [{"name": "customer", "to": "people.Contact"}]},
    {"id": "orders.Dashboard", "kind": "view", "name": "Dashboard",
     "settings": {"accent": "#5B5BF6"}}
  ],
  "edges": [
    {"from": "orders.Dashboard", "to": "orders.Order", "kind": "shows"}
  ]
}
```

- The export holds structure and settings. It never holds a node's code.
- Importing it builds the same structure from templates, with the same settings. **planned**

## 23.6 Who sees the code

- The model, and the members of a space with the roles the space chooses.
- Never the public, and never an app that did not write it.
- A `secret` cell is read only by the space's human owners and editors, never by an agent
  or anyone else (**built**). Logic that must stay private runs on the server.

## 23.7 Tests

Built: cell kinds from the code (atlas tests); `param` and `tuneParam` (t_views).

Planned (each one is a task):
- The graph of the tasks app (`sdk/vajra/README.md`, "A whole app") has a Record node
  `Task`, a View node `Tasks`, and a `shows` link from `Tasks` to `Task`.
- Changing a setting in the graph writes one new version of one cell, and the app shows
  the new value.
- An exported JSON holds no line of any node's code.
- Importing an export into an empty space gives a graph equal to the original's.
- A person who is not a member of the space gets the graph of an `open` app, never its
  `secret` cells.
