## The standard icon set: SVG path data on a 24×24 grid, drawn as strokes.
## Written for Yantra (simple geometric forms, stroke 1.8–2); `icon "name"` in a
## UI block draws one. Unknown names draw nothing.

const iconData = [
  ("search", "M11 4 A7 7 0 1 1 11 18 A7 7 0 1 1 11 4 Z M16.5 16.5 L21 21"),
  ("plus", "M12 5 V19 M5 12 H19"),
  ("x", "M6 6 L18 18 M18 6 L6 18"),
  ("check", "M5 12.5 L10 17 L19 7"),
  ("home", "M3 11 L12 4 L21 11 M5.5 9.5 V20 H18.5 V9.5 M10 20 V14 H14 V20"),
  ("grid", "M4 4 H10 V10 H4 Z M14 4 H20 V10 H14 Z M4 14 H10 V20 H4 Z M14 14 H20 V20 H14 Z"),
  ("list", "M9 6 H20 M9 12 H20 M9 18 H20 M4.5 6 H5 M4.5 12 H5 M4.5 18 H5"),
  ("sun", "M12 8 A4 4 0 1 1 12 16 A4 4 0 1 1 12 8 Z M12 2.5 V4.5 M12 19.5 V21.5 M2.5 12 H4.5 M19.5 12 H21.5 M5.3 5.3 L6.7 6.7 M17.3 17.3 L18.7 18.7 M5.3 18.7 L6.7 17.3 M17.3 6.7 L18.7 5.3"),
  ("moon", "M20 14.5 A8.5 8.5 0 1 1 9.5 4 A6.5 6.5 0 0 0 20 14.5 Z"),
  ("palette", "M12 3 A9 9 0 1 0 12 21 C13.4 21 14 20.2 14 19.2 C14 18 13.2 17.4 13.2 16.4 C13.2 15.3 14.1 14.5 15.2 14.5 H17 A4 4 0 0 0 21 10.5 C21 6.3 17 3 12 3 Z M7.5 11 H7.6 M9.8 7.2 H9.9 M14.6 7.4 H14.7"),
  ("sliders", "M4 6 H13 M17 6 H20 M15 4 V8 M4 12 H7 M11 12 H20 M9 10 V14 M4 18 H15 M19 18 H20 M17 16 V20"),
  ("folder", "M3 7 A2 2 0 0 1 5 5 H9.5 L11.5 7 H19 A2 2 0 0 1 21 9 V17 A2 2 0 0 1 19 19 H5 A2 2 0 0 1 3 17 Z"),
  ("file", "M14 3 H7 A2 2 0 0 0 5 5 V19 A2 2 0 0 0 7 21 H17 A2 2 0 0 0 19 19 V8 Z M14 3 V8 H19"),
  ("chevronRight", "M9 6 L15 12 L9 18"),
  ("chevronLeft", "M15 6 L9 12 L15 18"),
  ("chevronDown", "M6 9 L12 15 L18 9"),
  ("arrowRight", "M5 12 H19 M13 6 L19 12 L13 18"),
  ("arrowLeft", "M19 12 H5 M11 6 L5 12 L11 18"),
  ("refresh", "M20 12 A8 8 0 1 1 17.7 6.3 M20 4 V9 H15"),
  ("trash", "M4 7 H20 M10 11 V17 M14 11 V17 M6 7 L7 20 H17 L18 7 M9 7 V4 H15 V7"),
  ("star", "M12 3.5 L14.6 8.8 L20.5 9.6 L16.2 13.7 L17.3 19.5 L12 16.7 L6.7 19.5 L7.8 13.7 L3.5 9.6 L9.4 8.8 Z"),
  ("clock", "M12 3 A9 9 0 1 1 12 21 A9 9 0 1 1 12 3 Z M12 7 V12 L15.5 14"),
  ("bell", "M6 16 V11 A6 6 0 0 1 18 11 V16 L19.5 18 H4.5 Z M10 21 H14"),
  ("command", "M9 6 A3 3 0 1 0 6 9 H18 A3 3 0 1 0 15 6 V18 A3 3 0 1 0 18 15 H6 A3 3 0 1 0 9 18 Z"),
  ("sidebar", "M4 5 H20 V19 H4 Z M9.5 5 V19"),
  ("layers", "M12 3 L21 8 L12 13 L3 8 Z M3 12.5 L12 17.5 L21 12.5 M3 16.5 L12 21.5 L21 16.5"),
  ("calculator", "M6 3 H18 A1 1 0 0 1 19 4 V20 A1 1 0 0 1 18 21 H6 A1 1 0 0 1 5 20 V4 A1 1 0 0 1 6 3 Z M8.5 7 H15.5 M8.5 12 H8.6 M12 12 H12.1 M15.5 12 H15.6 M8.5 16 H8.6 M12 16 H12.1 M15.5 16 H15.6"),
  ("checkSquare", "M5 4 H19 A1 1 0 0 1 20 5 V19 A1 1 0 0 1 19 20 H5 A1 1 0 0 1 4 19 V5 A1 1 0 0 1 5 4 Z M8 12 L11 15 L16 9"),
  ("presentation", "M3 4 H21 M5 4 V15 H19 V4 M12 15 V20 M8.5 20 H15.5"),
  ("activity", "M3 12 H7 L10 5 L14 19 L17 12 H21"),
  ("sparkles", "M12 3 L13.8 8.2 L19 10 L13.8 11.8 L12 17 L10.2 11.8 L5 10 L10.2 8.2 Z M18.5 16 L19.2 17.8 L21 18.5 L19.2 19.2 L18.5 21 L17.8 19.2 L16 18.5 L17.8 17.8 Z"),
  ("box", "M12 3 L20 7.5 V16.5 L12 21 L4 16.5 V7.5 Z M4 7.5 L12 12 L20 7.5 M12 12 V21"),
  ("shield", "M12 3 L19 6 V11.5 C19 16 16 19.5 12 21 C8 19.5 5 16 5 11.5 V6 Z M9 12 L11.2 14.2 L15.5 9.8"),
  ("terminal", "M4 5 H20 V19 H4 Z M8 10 L11 12.5 L8 15 M13 15 H16"),
  ("globe", "M12 3 A9 9 0 1 1 12 21 A9 9 0 1 1 12 3 Z M3 12 H21 M12 3 C9.5 5.5 9.5 18.5 12 21 C14.5 18.5 14.5 5.5 12 3 Z"),
  ("dot", "M12 10.5 A1.5 1.5 0 1 1 12 13.5 A1.5 1.5 0 1 1 12 10.5 Z"),
  ("power", "M12 3 V12 M7.5 6.2 A8 8 0 1 0 16.5 6.2"),
  ("split", "M4 5 H20 V19 H4 Z M12 5 V19"),
  ("yantra", "M12 2.5 L20.5 7.25 L20.5 16.75 L12 21.5 L3.5 16.75 L3.5 7.25 Z M12 12 V21.5 M12 12 L3.5 7.25 M12 12 L20.5 7.25"),  # a cube; its inner edges are a Y
  ("minus", "M5 12 H19"),
  ("square", "M6 6 H18 V18 H6 Z"),
  ("wifi", "M2 8.8 A15 15 0 0 1 22 8.8 M5 12.5 A10 10 0 0 1 19 12.5 M8.5 16 A5 5 0 0 1 15.5 16 M12 20 H12.01"),
  ("wifiOff", "M2 2 L22 22 M8.5 16 A5 5 0 0 1 15.5 16 M5 12.5 A10 10 0 0 1 11 9.6 M16.7 10.7 A10 10 0 0 1 19 12.5 M12 20 H12.01"),
  ("ethernet", "M8 3 H16 V9 H19 V21 H5 V9 H8 Z M9 15 V17 M12 15 V17 M15 15 V17"),
  ("volume", "M11 5 L6 9 H2 V15 H6 L11 19 Z M15.5 8.5 A5 5 0 0 1 15.5 15.5 M19 5 A10 10 0 0 1 19 19"),
  ("volumeX", "M11 5 L6 9 H2 V15 H6 L11 19 Z M22 9 L16 15 M16 9 L22 15"),
  ("battery", "M3 7 H18 V17 H3 Z M21 11 V13"),
  ("batteryCharging", "M3 7 H18 V17 H3 Z M21 11 V13 M11 8.5 L8 12.5 H12 L9 15.5"),
  ("moon", "M12 3 A9 9 0 1 0 21 12.8 A7 7 0 0 1 12 3 Z"),
  ("cpu", "M7 7 H17 V17 H7 Z M10 10 H14 V14 H10 Z M9 3 V7 M15 3 V7 M9 17 V21 M15 17 V21 M3 9 H7 M3 15 H7 M17 9 H21 M17 15 H21"),
  ("hardDrive", "M3 13 H21 V19 H3 Z M5.5 13 L8 5 H16 L18.5 13 M7 16 H7.01 M10 16 H10.01"),
  ("lock", "M5 11 H19 V21 H5 Z M8 11 V8 A4 4 0 0 1 16 8 V11"),
  ("arrowUpRight", "M7 17 L17 7 M9 7 H17 V15"),
  ("expand", "M14 4 H20 V10 M10 20 H4 V14 M20 4 L13.5 10.5 M4 20 L10.5 13.5"),
]

proc iconPath*(name: string): string =
  ## The SVG path data for a named icon, or "" if there is no such icon.
  for (n, d) in iconData:
    if n == name: return d
  ""

proc iconNames*(): seq[string] =
  for (n, _) in iconData: result.add n
