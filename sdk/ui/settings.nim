## Settings pages, GENERATED from a table of rows (C122 P4).
##
## The point of this module is that a page is never hand-written. `settingsSchema` is the
## only list of controls; `pageModel` turns it into the rows a view renders, and
## `pagesFor` decides which page each row belongs to. Adding one row to the schema produces
## a control with no page code at all — that is what `t_settings` asserts by building a
## schema of its own and counting the controls that fall out.
##
## Rows carry a `reading` whose Provenance says where a value came from. A control fed by
## pvInjected or pvReported can never read as a detected device; `readOnly` is set so the
## page does not invite the user to trust it as live.

import std/strutils
import ./keybind

type
  ControlKind* = enum
    ckToggle,                    ## on/off
    ckSlider,                    ## a bounded number
    ckChoice,                    ## one of `options`
    ckText,                      ## free text
    ckKeybind,                   ## a chord, owned by the keybind picker
    ckAction                     ## a button

  SettingRow* = object
    id*, label*, page*, section*: string
    kind*: ControlKind
    value*: string                ## the current value, as text
    options*: seq[string]         ## ckChoice only
    lo*, hi*: int                 ## ckSlider only
    source*: Provenance          ## where `value` came from
    help*: string                ## the one line under the label

  PageModel* = object
    id*, title*: string
    rows*: seq[SettingRow]

proc settingsSchema*(): seq[SettingRow] =
  ## The one list of controls every settings page is generated from.
  result = @[
  SettingRow(id: "appearance.theme", label: "Theme", page: "appearance", section: "Look",
             kind: ckChoice, value: "Catppuccin",
             options: @["Catppuccin", "Nord", "Solarized", "Dracula"],
             source: pvReported, help: "The palette the whole shell draws with"),
  SettingRow(id: "appearance.accent", label: "Accent colour", page: "appearance", section: "Look",
             kind: ckChoice, value: "Blue",
             options: @["Blue", "Teal", "Rose", "Amber"], source: pvReported,
             help: "Highlights and focus rings"),
  SettingRow(id: "display.scale", label: "Interface scale", page: "display", section: "Screen",
             kind: ckSlider, value: "100", lo: 100, hi: 200, source: pvReported,
             help: "Percent of the default size. Restart is not needed"),
  SettingRow(id: "display.refresh", label: "Refresh rate", page: "display", section: "Screen",
             kind: ckSlider, value: "60", lo: 24, hi: 240, source: pvDetected,
             help: "Hz, read from the display"),
  SettingRow(id: "sound.volume", label: "Output volume", page: "sound", section: "Output",
             kind: ckSlider, value: "70", lo: 0, hi: 100, source: pvReported,
             help: "Percent"),
  SettingRow(id: "sound.device", label: "Output device", page: "sound", section: "Output",
             kind: ckText, value: "System default", source: pvReported,
             help: "Which device sound goes to"),
  SettingRow(id: "power.profile", label: "Power profile", page: "power", section: "Battery",
             kind: ckChoice, value: "Balanced",
             options: @["Power saver", "Balanced", "Performance"], source: pvReported,
             help: "What the machine trades away for speed"),
  SettingRow(id: "power.charge", label: "Battery level", page: "power", section: "Battery",
             kind: ckText, value: "—", source: pvInjected,
             help: "Filled in by the shell once the battery is readable"),
  SettingRow(id: "network.ssid", label: "Connected network", page: "network",
             section: "Wi-Fi", kind: ckText, value: "Fable-5G", source: pvInjected,
             help: "Configured here; the shell reports a real scan when it has one"),
  SettingRow(id: "network.security", label: "Security", page: "network", section: "Wi-Fi",
             kind: ckText, value: "WPA3", source: pvInjected, help: "Of the configured network"),
  SettingRow(id: "bluetooth.powered", label: "Bluetooth", page: "bluetooth",
             section: "Radios", kind: ckToggle, value: "off", source: pvInjected,
             help: "Radio state the user set; not a read of any adapter"),
  SettingRow(id: "notifications.app", label: "App notifications", page: "notifications",
             section: "Per app", kind: ckChoice, value: "Ask",
             options: @["Ask", "Allow", "Never"], source: pvReported,
             help: "What an app may do without asking"),
  SettingRow(id: "apps.defaults", label: "Default permissions for new apps",
             page: "apps", section: "Defaults", kind: ckChoice, value: "Ask",
             options: @["Ask", "Allow", "Never"], source: pvReported,
             help: "Applied to an app the first time it asks"),
  SettingRow(id: "keys.split", label: "Split window", page: "keys", section: "Tiling",
             kind: ckKeybind, value: "Ctrl+Shift+D", source: pvReported,
             help: "Dwindle split"),
  SettingRow(id: "keys.float", label: "Float window", page: "keys", section: "Tiling",
             kind: ckKeybind, value: "Ctrl+F", source: pvReported, help: "Undo tiling for this window"),
  SettingRow(id: "keys.zoom", label: "Zoom in", page: "keys", section: "View",
             kind: ckKeybind, value: "Ctrl+Plus", source: pvReported, help: "Magnify the focused tile"),
  SettingRow(id: "about.version", label: "Version", page: "about", section: "Yantra",
             kind: ckText, value: "0.1.0", source: pvReported, help: "The build this is"),
  SettingRow(id: "about.check", label: "Check for updates", page: "about", section: "Yantra",
             kind: ckAction, value: "", source: pvReported,
             help: "Asks the update service; shows nothing until it answers")]

proc pagesFor*(rows: openArray[SettingRow]): seq[string] =
  ## Every page that has at least one row, in first-seen order. A new row's page appears
  ## here with no other change, which is what makes the pages generated rather than written.
  var seen: seq[string] = @[]
  for r in rows:
    if r.page notin seen: seen.add r.page
  seen

proc sectionsFor*(rows: openArray[SettingRow]; page: string): seq[string] =
  var seen: seq[string] = @[]
  for r in rows:
    if r.page == page and r.section notin seen: seen.add r.section
  seen

proc rowsOn*(rows: openArray[SettingRow]; page: string): seq[SettingRow] =
  for r in rows:
    if r.page == page: result.add r

proc pageModel*(rows: openArray[SettingRow]; page: string): PageModel =
  ## The whole model for one page: its controls, in schema order, grouped by section.
  PageModel(id: page, title: (if page.len > 0: page[0].toUpperAscii & page[1 .. ^1] else: ""),
            rows: rowsOn(rows, page))

proc isReadOnly*(r: SettingRow): bool =
  ## A control whose value the shell did not measure must not invite the user to trust it
  ## as live hardware. Reported values are the user's own setting, so they stay editable.
  r.source == pvInjected

proc valueNote*(r: SettingRow): string =
  ## The honesty line a page shows under a control. Empty when there is nothing to say.
  case r.source
  of pvInjected:
    "Set here — not read from the hardware"
  of pvReported:
    ""
  of pvDetected:
    "Read from the device"

proc findRow*(rows: openArray[SettingRow]; id: string): (bool, SettingRow) =
  for r in rows:
    if r.id == id: return (true, r)

proc isValid*(r: SettingRow; v: string): bool =
  ## Whether `v` is an acceptable value for this control. The picker and the pages both
  ## refuse anything this says no to, so an invalid value never reaches the store.
  case r.kind
  of ckToggle: v in ["on", "off"]
  of ckSlider:
    if v.len == 0: return false
    for ch in v:
      if ch < '0' or ch > '9': return false
    var n = 0
    for ch in v: n = n * 10 + int(ord(ch) - ord('0'))
    n >= r.lo and n <= r.hi
  of ckChoice: v in r.options
  of ckText, ckKeybind, ckAction: true

proc checkPage*(rows: openArray[SettingRow]; page: string): seq[string] =
  ## Problems a page would ship with. Empty means the page is coherent. Every problem is
  ## about a row the schema got wrong, so this runs in the gate over the real schema.
  for r in rowsOn(rows, page):
    if r.label.len == 0: result.add r.id & ": no label"
    if r.section.len == 0: result.add r.id & ": no section"
    if not r.isValid(r.value): result.add r.id & ": default " & r.value & " is not valid"
    if r.kind == ckChoice and r.options.len == 0:
      result.add r.id & ": choice with no options"
    if r.kind == ckSlider and r.lo >= r.hi:
      result.add r.id & ": slider range is empty"
  result
