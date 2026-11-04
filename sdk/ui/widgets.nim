## Yantra SDK UI Widgets (R3)
import ../core/runtime
export runtime

proc setText*(node: Node, value: string) = node.set(pText, value)
proc width*(node: Node, value: int32) = node.set(pWidth, value)
proc height*(node: Node, value: int32) = node.set(pHeight, value)

proc window*(title: string, w: int32 = 800, h: int32 = 600): Node =
  result = make(nkWindow); result.setText(title); result.width(w); result.height(h)

proc column*(parent: Node): Node = make(nkColumn, parent)
proc row*(parent: Node): Node = make(nkRow, parent)
proc text*(parent: Node, content: string): Node =
  result = make(nkText, parent); result.setText(content)
proc button*(parent: Node, label: string): Node =
  result = make(nkButton, parent); result.setText(label)
proc image*(parent: Node, src: string): Node =
  result = make(nkImage, parent); result.setText(src); result.set(pSource, src)
proc input*(parent: Node, hintText: string = ""): Node =
  result = make(nkInput, parent); result.setText(hintText)
proc panel*(parent: Node, w: int32 = 0, h: int32 = 0): Node =
  result = make(nkPanel, parent)
  if w > 0: result.width(w)
  if h > 0: result.height(h)
proc divider*(parent: Node, w: int32 = 0): Node {.discardable.} = panel(parent, w, 1)
proc spacer*(parent: Node, h: int32 = 8): Node {.discardable.} =
  result = make(nkSpacer, parent)
  if h > 0: result.height(h)
