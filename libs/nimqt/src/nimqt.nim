## nimqt — Nim access to Qt6 QML / Qt Quick.
##
## Umbrella module: re-exports the low-level bindings (QtCore, QtGui, QtQml,
## QtQuick), the high-level wrappers, marshaling and the signal bridge.
##
## Quick start:
##
## ```nim
## import nimqt
##
## let app = newApplication()
## let engine = newEngine()
## let component = engine.newComponentFromString("""
##   import QtQuick
##   Rectangle { width: 200; height: 100; color: "steelblue" }
## """)
## let item = component.createObject()
## ```

import nimqt/QtCore
import nimqt/QtGui
import nimqt/QtQml
import nimqt/QtQuick
import nimqt/marshaling
import nimqt/signals
import nimqt/wrappers

export QtCore, QtGui, QtQml, QtQuick, marshaling, signals, wrappers
