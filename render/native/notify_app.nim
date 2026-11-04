import yantra

needs notifications

var notifyStatus = newState("idle")

app "Notify App":
  column:
    text notifyStatus.get()
    button "Send Notify":
      onClick:
        if notify("Build Complete", "App compiled successfully"):
          notifyStatus.set("sent ok")
        else:
          notifyStatus.set("sent failed")
