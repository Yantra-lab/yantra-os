# VISUAL PARITY AUDIT — Opus vs port (read-only, 2026-11-05)
Sources: opus-ref.png + opus-solo.png vs desk-cael/embedded/appview-long/clean-tab/warm1/probe-av; tree apps/desktop/; worktree originals (intent only). All file:line = OUR tree. Ordered by visual impact.

## 1) Right Caelestia bar — incomplete (highest impact)
Opus x~1865-1920: jewel 44px gradient y15-60; workspaces pill y75-305 (numbers 1-5, active primary pill + mini app icons, occupied containerHighest, empty outline); middle y395-695 three 80x80 r24 (lock / yantra-mark / power); bottom: Wed 10px/500 tertiary + 5 15px/600, hairline, 03+56 stacked 16px/600, wifi/volume/battery/sliders 16px, red power circle 40px.
Ours: jewel + 1-5 OK, no app icons; middle y260-650 EMPTY black gap; bottom only file-icon + Wed/5 + time + sliders + power — wifi/volume/battery MISSING; date/clock TEAL not pink.
Source: ui.nim:443-474 Dock(), :400-414 BarClock(), :350-398 Workspaces(), :553-579 SessionPanel() (drawer-only); state.nim:53-94 stubs return -1/netUnknown/"" so ui.nim:455-460 always false; config.nim:373 tertiary 0x7FC4C4 vs Opus pink, :369 onPrimary 0x201A30 vs 0x2A2A60, :368 primaryContainer 0x4A4458 vs 0x3F3F76, :379 errorContainer 0x5A1D28 vs 0x93000A.
Fix (worktree config.nim:17-25): primary 0xC2C1FF, onPrimary 0x2A2A60, primaryContainer 0x3F3F76, onPrimaryContainer 0xE2DFFF, secondaryContainer 0x45455C, onSecondaryContainer 0xE3E0FA, tertiary 0xF5B2E0, errorRole 0xFFB4AB, errorContainer 0x93000A, stateHover rgba(0xE5E1E7,0.08); restore live sys readings or force-show unknown-state icons.

## 2) Wallpaper gradient — too dark/cool
Opus: base m3surface #131317, indigo glow bottom-left, lavender-rose mist top-right, grain, no emblem. Clock ~90px + date 20px/500 bottom-left.
Ours: base #07080E→#0B0D17, blue-grey, rose too weak.
Source: app.nim:11-27 SKSL (a/b/c weights), config.nim:202-233 bakeCelestiaWallpaper() UNUSED; app.nim:31 bg m3surface uses port 0x14141C.
Fix: keep SKSL, retune base #131317, a@(0.15,0.95) w~0.55 primary-tinted, b@(0.95,0.10) w~0.55 tertiary-pink; m3surface 0x14141C→0x131317, containerLowest 0x0E0E12.

## 3) Black dead windows vs tiled content
Opus: Notes list + body + Library grid with Open pills all render. Ours: frame visible, body black = deadEngine placeholder (clean-tab.png DOES render Notes — tiling works when address resolves).
Source: catalog.nim:134-145, state.nim:141-150 appOf(), :397-414 winRect(), ui.nim:753-767 WindowBody appview.
Fix: no token change — ensure y:notes/y:library resolve to built app.wasm.

## 4) Left sidebar too wide + wrong focused fill
Opus w272: Space 1 header + nav pill 36h r18 + search 40h r12 + folder rows 32h r16 + New Tab 38h r19 + bottom jewels 40px. Ours 28px too wide; focused fill low contrast.
Source: config.nim:394 sidebarWidth 300 vs worktree 272; ui.nim:86-100 TabRow, :280-285 WideSidebar, :251-262 Logo.
Fix: sidebarWidth 300→272; ui.nim:88 focused fill containerHigh→secondaryContainer.

## 5) Address bar duality + placement
Opus Library: label 14px/600 + big pill 56h r28 + primary arrow circle 44px. Ours: two inputs (WideSidebar AddressBar 40h r12 vs SearchPill 56h r28 — geometry EXACT in SearchPill). LibraryPage uses big SearchPill correctly.
Source: ui.nim:176-201,68-80, state.nim:38/44, :228-239 goAddress.
Fix: keep both by design; ensure draft cleared; placeholder logic as-is.

## 6) Window chrome radii/gaps/border/shadow
Opus: windowRadius 15, cardRadius 16, gapsOut 10, gapsIn 8, frameWidth 10, screenRadius 25, border 1px outlineVariant #47464F, shadow y4 b15 a0.25.
Ours: windowRadius 12, cardRadius 20, gapsOut 12, gapsIn 6, frameWidth 12, screenRadius 24, border 1.5px glow, shadow y8 b28 a0.40.
Source: config.nim:31-36/86-97/391-398, app.nim:40/48-51/62-70.
Fix: frameWidth 12→10, screenRadius 24→25, gapsOut 12→10, gapsIn 6→8, windowRadius 12→15, cardRadius 20→16, borderSize 1.5→1.0, cornerRadius 10→15, focused border rgba(primary,0.9)→outlineVariant/rgba(primary,0.35), shadow →y4 b15 a0.25. titleHeight 36 already correct.

## 7) Buttons/pills
Opus: New amber 32h r16 #F4D078 onPrimary; Open 30h r15 primary #C2C1FF onPrimary #2A2A60 12px/600; tonal radius size*3/10 fill rgba(tint,0.18).
Ours: LibraryCard 240x72 r20 too bubbly; Open shape right, wrong onPrimary.
Fix: cardRadius 20→16, onPrimary →0x2A2A60 (see #1).

## 8) Fonts + motion (subtle, pervasive)
Opus: Segoe UI Variable Text/Display + Cascadia Mono, moveMs 350, effectMs 200.
Ours: Segoe UI / Consolas, moveMs 240, effectMs 180; mTextW 0.51/0.58 assumes Variable.
Fix: restore Variable Text/Display + Cascadia Mono, effectMs→200 moveMs→350.
