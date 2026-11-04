# nimyoga INTERFACE

## Types
- `FlexDirection`: `fdColumn`, `fdColumnReverse`, `fdRow`, `fdRowReverse`
- `Edge`: `edgeLeft`, `edgeTop`, `edgeRight`, `edgeBottom`, `edgeStart`, `edgeEnd`, `edgeHorizontal`, `edgeVertical`, `edgeAll`
- `Gutter`: `gutterColumn`, `gutterRow`, `gutterAll`
- `Direction`: `dirInherit`, `dirLTR`, `dirRTL`
- `LayoutResult`: `left`, `top`, `width`, `height` (float32)
- `YogaNode`: wrapper around `YGNodeRef`

## Procs
- `newNode*(): YogaNode`
- `free*(node: YogaNode; recursive = false)`
- `insertChild*(node, child: YogaNode; index: int)`
- `removeChild*(node, child: YogaNode)`
- `setFlexDirection*(node: YogaNode; dir: FlexDirection)`
- `setWidth*(node: YogaNode; width: float32)`
- `setHeight*(node: YogaNode; height: float32)`
- `setFlexGrow*(node: YogaNode; grow: float32)`
- `setPadding*(node: YogaNode; edge: Edge; padding: float32)`
- `setGap*(node: YogaNode; gutter: Gutter; gap: float32)`
- `calculateLayout*(node: YogaNode; availableWidth = NaN; availableHeight = NaN; dir = dirLTR)`
- `layout*(node: YogaNode): LayoutResult`
- `rawOf*(n): pointer`, `childAt*(n; i): pointer`, `removeChildAt*(n; child: pointer)` — child identity and removal by C node
- `detach*(n)` — remove from its owner, if any; `hasOwner*(n): bool`
- `copyStyle*(dst, src)` — YGNodeCopyStyle: restyle a node in place, keeping its children and caches
- `isDirty*(n): bool`
