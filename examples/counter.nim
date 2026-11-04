app "Counter":
  var clicks = state 0

  column(gap = 12, pad = 24):
    text "Clicked {clicks} times", size = 32
    button "Click me":
      onClick: clicks += 1
