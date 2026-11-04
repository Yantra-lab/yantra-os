import yantra

var dropMsg = newState("idle")
var dropCount = newState(0)

app "DnD App":
  column:
    text dropMsg.get()
    text "count: " & $dropCount.get()
    button "Source":
      onDragStart:
        setDragData("card-item")
        dropMsg.set("dragging card-item")
    panel(width = 200.px, height = 100.px):
      text "Drop Target"
      onDragOver:
        dropMsg.set("over target")
      onDrop:
        let d = droppedData()
        let name = droppedName()
        if name.len > 0:
          dropMsg.set("dropped file " & name & ":" & d)
        else:
          dropMsg.set("dropped node " & d)
        dropCount.set(dropCount.get() + 1)
