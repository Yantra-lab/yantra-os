import std/[strutils, os]
import schema

proc writeSdkWire() =
  var outStr = "## GENERATED FILE. DO NOT EDIT.\n"
  outStr.add "## Edit protocol/schema.nim instead.\n\n"
  outStr.add "type\n"
  
  outStr.add "  NodeKind* {.size: sizeof(int32).} = enum\n"
  for i, name in NodeKinds:
    outStr.add "    nk" & name & " = " & $i & "\n"
    
  outStr.add "\n  Prop* {.size: sizeof(int32).} = enum\n"
  for i, name in Props:
    outStr.add "    p" & name & " = " & $i & "\n"
    
  outStr.add "\n  Event* {.size: sizeof(int32).} = enum\n"
  for i, name in Events:
    outStr.add "    ev" & name & " = " & $i & "\n"
    
  outStr.add "\n  Align* {.size: sizeof(int32).} = enum\n"
  for i, name in Aligns:
    outStr.add "    al" & name & " = " & $i & "\n"
    
  outStr.add "\n  Easing* {.size: sizeof(int32).} = enum\n"
  for i, name in Easings:
    outStr.add "    ease" & name & " = " & $i & "\n"

  createDir("../sdk/core")
  writeFile("../sdk/core/wire.nim", outStr)

proc writeRenderWire() =
  var outStr = "## GENERATED FILE. DO NOT EDIT.\n"
  outStr.add "## Edit protocol/schema.nim instead.\n\n"
  outStr.add "const\n"
  
  for i, name in NodeKinds:
    outStr.add "  K_" & name.toUpperAscii() & "* = " & $i & "'i32\n"
  outStr.add "\n"
  
  for i, name in Props:
    # Special cases in qmlgen for P_PAD_TOP vs PadTop
    var upperName = name.toUpperAscii()
    if name == "PadTop": upperName = "PAD_TOP"
    elif name == "PadRight": upperName = "PAD_RIGHT"
    elif name == "PadBottom": upperName = "PAD_BOTTOM"
    elif name == "PadLeft": upperName = "PAD_LEFT"
    elif name == "BorderColor": upperName = "BORDER_COLOR"
    elif name == "BorderWidth": upperName = "BORDER_WIDTH"
    elif name.startsWith("Anim"): upperName = "ANIM_" & name[4..^1].toUpperAscii()
    elif name == "Transition": upperName = "TRANSITION"
    elif name.startsWith("Trans"): upperName = "TRANS_" & name[5..^1].toUpperAscii()
    elif name == "RotX": upperName = "ROT_X"
    elif name == "RotY": upperName = "ROT_Y"
    elif name == "RotZ": upperName = "ROT_Z"
    elif name == "PosX": upperName = "POS_X"
    elif name == "PosY": upperName = "POS_Y"
    elif name == "PosZ": upperName = "POS_Z"
    
    outStr.add "  P_" & upperName & "* = " & $i & "'i32\n"
  outStr.add "\n"
  
  for i, name in Events:
    outStr.add "  E_" & name.toUpperAscii() & "* = " & $i & "'i32\n"

  writeFile("wire.nim", outStr)

proc writeJsWire() =
  var outStr = "// GENERATED FILE. DO NOT EDIT.\n"
  outStr.add "// Edit protocol/schema.nim instead.\n\n"
  
  outStr.add "export const K = {\n"
  for i, name in NodeKinds:
    outStr.add "  " & name.toUpperAscii() & ": " & $i & ",\n"
  outStr.add "};\n\n"
  
  outStr.add "export const P = {\n"
  for i, name in Props:
    outStr.add "  " & name.toUpperAscii() & ": " & $i & ",\n"
  outStr.add "};\n\n"
  
  outStr.add "export const E = {\n"
  for i, name in Events:
    outStr.add "  " & name.toUpperAscii() & ": " & $i & ",\n"
  outStr.add "};\n"

  writeFile("../examples/protocol.mjs", outStr)
  writeFile("../web/runner/protocol.mjs", outStr)   # the web runner ships its own copy

proc writePropsRef() =
  let md = formatPropsMarkdown()
  writeFile("props.md", md)
  createDir("../docs/HOW_IT_WORKS")
  writeFile("../docs/HOW_IT_WORKS/props.md", md)

  var sdkProps = "## GENERATED FILE. DO NOT EDIT.\n## Edit protocol/schema.nim instead.\n\n"
  sdkProps.add "const SdkPropCount* = " & $PropTable.len & "\n"
  writeFile("../sdk/props.nim", sdkProps)

proc writeVajraWire() =
  ## The same protocol for Vajra (Nimony): the view plugin checks components,
  ## properties and events against these tables at compile time.
  var o = "## GENERATED FILE. DO NOT EDIT.\n## Edit protocol/schema.nim instead.\n\n"
  o.add "const\n  VjKinds* = ["
  for i, name in NodeKinds: o.add (if i > 0: ", " else: "") & "\"" & name & "\""
  o.add "]\n  VjEvents* = ["
  for i, name in Events: o.add (if i > 0: ", " else: "") & "\"" & name & "\""
  o.add "]\n  ## (Vajra name, wire property id, value type, components allowed or \"*\")\n"
  o.add "  VjProps* = [\n"
  for i, m in PropTable:
    o.add "    (\"" & m.dslName & "\", " & $Props.find(m.wireProp) & "'i32, \"" & m.propType &
      "\", \"" & m.allowedNodes & "\")" & (if i < PropTable.high: ",\n" else: "\n")
  o.add "  ]\n\n"
  # The same enums the Nim SDK has (NodeKind, Prop, Event, Align, Easing), so engine
  # code ported from it keeps its names: nkCanvas, pDraw, evFrame, alRight.
  let sdk = readFile("../sdk/core/wire.nim")
  o.add sdk[sdk.find("type\n") .. ^1]
  createDir("../sdk/vajra")
  writeFile("../sdk/vajra/wire.nim", o)

proc main() =
  writeSdkWire()
  writeVajraWire()                # after writeSdkWire: it repeats the SDK's enums
  writeRenderWire()
  writeJsWire()
  writePropsRef()
  echo "Wire protocol generated successfully."

main()
