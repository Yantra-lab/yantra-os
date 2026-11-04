## Themes: plain values in a signal (docs/spec/style.md §4).
##
## `theme()` reads the current theme and is tracked, so any prop written as
## `fill = theme().surface` is an effect that re-runs when the theme changes:
## `setTheme("Paper")` re-styles the whole app at once, with no engine work.

import ../core/signals, ../core/runtime


type Theme* = object
  name*: string
  dark*: bool
  bg*: int           ## the window
  sidebar*: int      ## side panels, a step off the window
  surface*: int      ## cards, rows, inputs
  surface2*: int     ## hover
  surface3*: int     ## pressed / selected
  line*: int         ## hairlines and borders
  text*: int
  muted*: int
  faint*: int
  accent*: int
  accentText*: int   ## text on the accent
  accentSoft*: int   ## accent at low opacity: selection, focus rings
  danger*: int
  success*: int
  radius*: int
  font*: string
  mono*: string

const themes* = [
  Theme(name: "Midnight", dark: true, bg: 0x0B0B10, sidebar: 0x0F0F15, surface: 0x16161D, surface2: 0x1E1E27,
        surface3: 0x282833, line: 0x26262F, text: 0xF5F5F7, muted: 0x8C8C96, faint: 0x5A5A64,
        accent: 0xFFB23E, accentText: 0x1A1206, accentSoft: 0x2AFFB23E, danger: 0xFF6B5E, success: 0x44D07B,
        radius: 10, font: "Segoe UI", mono: "Consolas"),
  Theme(name: "Paper", dark: false, bg: 0xF6F4EF, sidebar: 0xEDEAE2, surface: 0xFFFFFF, surface2: 0xF3F0E9,
        surface3: 0xE8E4DA, line: 0xE2DDD2, text: 0x1D1B18, muted: 0x6F6A61, faint: 0xA7A296,
        accent: 0xD9480F, accentText: 0xFFFFFF, accentSoft: 0x22D9480F, danger: 0xC92A2A, success: 0x2B8A3E,
        radius: 8, font: "Segoe UI", mono: "Consolas"),
  Theme(name: "Fjord", dark: true, bg: 0x2E3440, sidebar: 0x292E39, surface: 0x3B4252, surface2: 0x434C5E,
        surface3: 0x4C566A, line: 0x4C566A, text: 0xECEFF4, muted: 0xAEB6C5, faint: 0x7B8496,
        accent: 0x88C0D0, accentText: 0x2E3440, accentSoft: 0x3388C0D0, danger: 0xBF616A, success: 0xA3BE8C,
        radius: 8, font: "Segoe UI", mono: "Consolas"),
  Theme(name: "Ember", dark: true, bg: 0x140C0A, sidebar: 0x1A0F0C, surface: 0x241612, surface2: 0x2F1C16,
        surface3: 0x3B241C, line: 0x3A2620, text: 0xFBEFEA, muted: 0xC19E92, faint: 0x7E5F55,
        accent: 0xFF5A36, accentText: 0x1A0703, accentSoft: 0x33FF5A36, danger: 0xFF4D6A, success: 0x6BCB77,
        radius: 14, font: "Segoe UI", mono: "Consolas"),
  Theme(name: "Forest", dark: true, bg: 0x0C130F, sidebar: 0x0F1813, surface: 0x15201A, surface2: 0x1C2A22,
        surface3: 0x24352B, line: 0x22322A, text: 0xEAF3EC, muted: 0x9DB5A5, faint: 0x5E7466,
        accent: 0x7BD88F, accentText: 0x08150C, accentSoft: 0x2E7BD88F, danger: 0xF07167, success: 0x7BD88F,
        radius: 12, font: "Segoe UI", mono: "Consolas"),
  Theme(name: "Blossom", dark: false, bg: 0xFFF5F7, sidebar: 0xFCE9EE, surface: 0xFFFFFF, surface2: 0xFBEDF2,
        surface3: 0xF5DAE3, line: 0xF1D5E0, text: 0x2A1A21, muted: 0x87606F, faint: 0xC0A0AC,
        accent: 0xE0457B, accentText: 0xFFFFFF, accentSoft: 0x22E0457B, danger: 0xD6336C, success: 0x2F9E44,
        radius: 16, font: "Segoe UI", mono: "Consolas"),
  Theme(name: "Terminal", dark: true, bg: 0x000000, sidebar: 0x040804, surface: 0x081008, surface2: 0x0E1A0E,
        surface3: 0x142414, line: 0x1B3A1B, text: 0xA8FFA8, muted: 0x5CC85C, faint: 0x2F6B2F,
        accent: 0x39FF14, accentText: 0x000000, accentSoft: 0x2239FF14, danger: 0xFF5555, success: 0x39FF14,
        radius: 0, font: "Consolas", mono: "Consolas"),
  Theme(name: "Contrast", dark: true, bg: 0x000000, sidebar: 0x000000, surface: 0x000000, surface2: 0x1A1A1A,
        surface3: 0x333333, line: 0xFFFFFF, text: 0xFFFFFF, muted: 0xDDDDDD, faint: 0xAAAAAA,
        accent: 0xFFE600, accentText: 0x000000, accentSoft: 0x44FFE600, danger: 0xFF6B6B, success: 0x5CFF5C,
        radius: 4, font: "Segoe UI", mono: "Consolas"),
]

var currentTheme = state(themes[0])

proc theme*(): Theme =
  ## The current theme. Reading it inside a prop makes that prop follow theme changes.
  currentTheme.get()

proc announce(t: Theme) =
  ## Writes the theme's name on this app's window, where the engine picks it up and
  ## passes it to every app running inside this one (docs/spec/style.md §4).
  when not defined(yantraNoWindowTheme):
    Node(id: NodeId(0)).set(pTheme, t.name)

proc commit(t: Theme) =
  ## THE ONLY way the current theme changes.
  ##
  ## `announce` is not an optional extra here: it is the half of a theme change that
  ## the app itself cannot see. Setting the signal restyles THIS app; announcing is
  ## what tells the engine, which then pushes the name into every app running inside
  ## this one. An entry point that sets the signal without announcing therefore leaves
  ## nested apps on the previous theme — silent, and wrong in a way the author of the
  ## app cannot observe from inside it.
  ##
  ## So every public entry point goes through this one proc, and `currentTheme` is
  ## never written anywhere else. A new entry point cannot forget the announce: the
  ## only way to change the theme is to call `commit`, and `commit` always announces.
  ## The engine's reply path (`yantraTheme`) deliberately does NOT come through here
  ## — that is the host telling US to switch, so there is nothing to announce back.
  if currentTheme.peek() != t: announce(t)
  currentTheme.set(t)

proc setTheme*(t: Theme) = commit(t)

proc setTheme*(name: string) =
  for t in themes:
    if t.name == name:
      commit(t)
      return

proc nextTheme*() =
  ## Cycles through the built-in themes (a one-click theme switch).
  let cur = currentTheme.peek().name
  for i, t in themes:
    if t.name == cur:
      commit(themes[(i + 1) mod themes.len])
      return
  commit(themes[0])

proc themeNames*(): seq[string] =
  for t in themes: result.add t.name


var themeBuf: array[64, char]

proc yantraThemeBuf(): int32 {.exportc: "yantra_theme_buf".} =
  ## Where the engine writes the host's theme name before calling `yantra_theme`.
  ## (A buffer instead of an import, so apps that never read strings don't need
  ## `y_node_get_str`.)
  cast[int32](cast[uint](addr themeBuf[0]))

proc yantraTheme(n: int32) {.exportc: "yantra_theme".} =
  ## Called by the engine when the app that hosts this one switched theme: the new
  ## name (`n` bytes) is in `themeBuf`.
  var name = newString(clamp(int(n), 0, themeBuf.len))
  for i in 0 ..< name.len: name[i] = themeBuf[i]
  if name.len > 0 and name != currentTheme.peek().name:
    for t in themes:
      if t.name == name: currentTheme.set(t)
