import yantra

var content = newState("initial")
var statusMsg = newState("ready")

app "Text Editor":
  column:
    text statusMsg.get()
    text content.get()
    button "Open":
      onClick:
        pickFile("*.txt", proc(res: PickResult) =
          if res.ok:
            content.set(res.data)
            statusMsg.set("opened " & $res.data.len)
          else:
            statusMsg.set("open failed")
        )
    button "Save":
      onClick:
        saveFile(content.get(), "note.txt", "*.txt", proc(ok: bool) =
          if ok:
            statusMsg.set("saved successfully")
          else:
            statusMsg.set("save failed")
        )
