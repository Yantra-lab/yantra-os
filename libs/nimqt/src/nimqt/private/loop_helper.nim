## Shared helper for example apps: bounded event-loop pump when headless,
## real exec() otherwise. Importable as nimqt/private/loop_helper.

import os
import nimqt/QtCore, nimqt/QtGui, nimqt/wrappers

proc runAppLoop*(app: Application): int =
  ## Under offscreen platform there are no user-closeable windows, so pump a
  ## bounded number of events then exit cleanly (keeps CI/headless usable).
  if $guiappPlatformName(QGuiApplication).toString() == "offscreen":
    for i in 0 ..< 30:
      processEvents()
      sleep(10)
    echo "(offscreen: exiting after short pump)"
    return 0
  discard app.exec()
  return 0
