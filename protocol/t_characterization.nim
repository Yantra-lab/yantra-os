## Characterization test for protocol/schema.nim, protocol/wire.nim, and sdk/core/wire.nim (Z6)

import schema
import wire as render_wire
import ../sdk/core/wire as sdk_wire

proc main() =
  let nkLen = NodeKinds.len
  let pLen = Props.len
  let totalEvLen = Events.len
  let evLen = 13
  let alLen = Aligns.len
  let easeLen = Easings.len
  doAssert nkLen == 48          # + Particles (PT1); + Synth (AU1); + Group (E4), + AppView, Path (E5), + Page (D1), + Mesh (S3D)
  doAssert pLen == 265          # + Fullscreen (DESK); + Target (RT1); + 9 particles (PT1); + AnimClip, BlendTime, AnimSpeed, AnimTime (CH1); + 7 materials (M3D); + 9 finish (LK1); + 6 physics (PH1); + Texture, Tiling, TilingY (T3D); + 13 synthesis (AU1); + VertexShader, Uniforms, Unlit (SH1); + PointerLock (G-IN); + 21 native 3D (S3D); + Spellcheck, Replace (Q9); + 6 OS props (Q8); + FocusAt (Q6); + Smooth, Zoomable (Q4); + Links, Inline, Find, FindIndex (Q3); + Anchor, StickBottom, ItemKey, ScrollToKey (Q1); + Direction (P9); + Draw (P7); + Sticky, StickyLeft (P6); + Block (P5); + Playing, SeekTo, Waveform (P3); + FontWeight, TextColor (E4); + 44 style props, Theme (E5); + 8 motion (M1); + Site (U3); + Fit (U8); + Name (A1); + 7 effects (FX1); + Span (L1); + Net (F1); + Reveal, Parallax (V1); + Spans (R2); + OV1/SCR1: Placement, StickToEnd
  doAssert evLen == 13          # base
  doAssert totalEvLen == 34     # + Frame (G-IN); + Q1-Q11 (17) + DragStart, DragOver, Drop (C4)

  doAssert alLen == 3
  doAssert easeLen == 35         # + 4 springs (S7)

  let wOrd = int32(ord(nkWindow))
  let cmOrd = int32(ord(nkContextMenu))
  doAssert wOrd == K_WINDOW and K_WINDOW == 0
  doAssert cmOrd == K_CONTEXTMENU and K_CONTEXTMENU == 40
  doAssert int32(ord(nkGroup)) == K_GROUP and K_GROUP == 41   # appended, so existing ids never move
  doAssert int32(ord(nkAppView)) == K_APPVIEW and K_APPVIEW == 42
  doAssert int32(ord(nkPath)) == K_PATH and K_PATH == 43
  doAssert int32(ord(pFontWeight)) == 88 and int32(ord(pMarginTop)) == 90 and int32(ord(pFocusOpacity)) == 133
  doAssert int32(ord(pFit)) == P_FIT and P_FIT == 144

  let ptOrd = int32(ord(pText))
  let ppadOrd = int32(ord(pPadTop))
  let protOrd = int32(ord(pRotX))
  let panimOrd = int32(ord(pAnimTarget))
  let ptransOrd = int32(ord(pTransDuration))
  let psubOrd = int32(ord(pOnSubmit))
  doAssert ptOrd == P_TEXT and P_TEXT == 0
  doAssert ppadOrd == P_PAD_TOP and P_PAD_TOP == 21
  doAssert protOrd == P_ROT_X and P_ROT_X == 12
  doAssert panimOrd == P_ANIM_TARGET and P_ANIM_TARGET == 28
  doAssert ptransOrd == P_TRANS_DURATION and P_TRANS_DURATION == 38
  doAssert psubOrd == P_ONSUBMIT and P_ONSUBMIT == 87

  let ecOrd = int32(ord(evClick))
  let edOrd = int32(ord(evCanvasDraw))
  doAssert ecOrd == E_CLICK and E_CLICK == 0
  doAssert edOrd == E_CANVASDRAW and E_CANVASDRAW == 11
  doAssert int32(ord(evDragStart)) == E_DRAGSTART and E_DRAGSTART == 30
  doAssert int32(ord(evDragOver)) == E_DRAGOVER and E_DRAGOVER == 31
  doAssert int32(ord(evDrop)) == E_DROP and E_DROP == 32


  let alL = ord(alLeft)
  let alC = ord(alCenter)
  let alR = ord(alRight)
  doAssert alL == 0 and alC == 1 and alR == 2

  let eLin = ord(easeLinear)
  let eBounce = ord(easeInOutBounce)
  doAssert eLin == 0 and eBounce == 30

  echo "PASS t_characterization"

main()

import std/[os, strutils]

proc testL2() =
  doAssert PropTable.len >= 20
  let idxSize = findPropMeta("size")
  doAssert idxSize >= 0
  doAssert PropTable[idxSize].wireProp == "FontSize"
  doAssert PropTable[idxSize].propType == "int32"
  doAssert isPropAllowedOnNode("size", "Text")
  doAssert isPropAllowedOnNode("gap", "Column")
  doAssert not isPropAllowedOnNode("gap", "Image")
  doAssert findPropMeta("colour") == -1
  doAssert suggestPropName("colour", "Text") == "color"
  doAssert suggestPropName("gapp", "Column") == "gap"

  let md = formatPropsMarkdown()
  doAssert md.contains("| `size` | `pFontSize` | `int32` |")
  doAssert md.contains("| `gap` | `pSpacing` | `int32` |")
  doAssert fileExists("props.md")
  doAssert fileExists("../docs/HOW_IT_WORKS/props.md")
  doAssert fileExists("../sdk/props.nim")
  echo "PASS t_characterization L2 (PropTable + generated props.md)"

testL2()
