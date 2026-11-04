## Units as types (roadmap S1): `320.px`, `180.ms`, `1.5.s`, `90.deg`. A plain number still
## means px, ms or degrees, but a value WITH a unit must be the right one:
## `width = 200.ms` is a compile error, not a silent bug.

type
  Px* = distinct float32     ## a length in logical pixels
  Ms* = distinct float32     ## a duration in milliseconds
  Deg* = distinct float32    ## an angle in degrees, clockwise

template px*(x: SomeNumber): Px = Px(float32(x))
template ms*(x: SomeNumber): Ms = Ms(float32(x))
template s*(x: SomeNumber): Ms = Ms(float32(x) * 1000)
template secs*(x: SomeNumber): Ms = Ms(float32(x) * 1000)
template deg*(x: SomeNumber): Deg = Deg(float32(x))

proc `$`*(x: Px): string = $float32(x) & "px"
proc `$`*(x: Ms): string = $float32(x) & "ms"
proc `$`*(x: Deg): string = $float32(x) & "deg"
proc `+`*(a, b: Px): Px = Px(float32(a) + float32(b))
proc `-`*(a, b: Px): Px = Px(float32(a) - float32(b))
proc `*`*(a: Px; k: SomeNumber): Px = Px(float32(a) * float32(k))
proc `+`*(a, b: Ms): Ms = Ms(float32(a) + float32(b))
proc `*`*(a: Ms; k: SomeNumber): Ms = Ms(float32(a) * float32(k))
proc `==`*(a, b: Px): bool {.borrow.}
proc `==`*(a, b: Ms): bool {.borrow.}
proc `==`*(a, b: Deg): bool {.borrow.}

# What the DSL calls for each prop (sdk/ui/dsl.nim): the number the wire carries.
proc lengthOf*(x: SomeNumber): float32 = float32(x)
proc lengthOf*(x: Px): float32 = float32(x)
proc lengthOf*(x: Ms): float32 {.error: "Y020 this prop is a length: use px (e.g. 16.px), not ms".}
proc lengthOf*(x: Deg): float32 {.error: "Y020 this prop is a length: use px (e.g. 16.px), not deg".}

proc durationOf*(x: SomeNumber): float32 = float32(x)
proc durationOf*(x: Ms): float32 = float32(x)
proc durationOf*(x: Px): float32 {.error: "Y021 this prop is a duration: use ms or s (e.g. 200.ms), not px".}
proc durationOf*(x: Deg): float32 {.error: "Y021 this prop is a duration: use ms or s (e.g. 200.ms), not deg".}

proc angleOf*(x: SomeNumber): float32 = float32(x)
proc angleOf*(x: Deg): float32 = float32(x)
proc angleOf*(x: Px): float32 {.error: "Y022 this prop is an angle: use deg (e.g. 45.deg), not px".}
proc angleOf*(x: Ms): float32 {.error: "Y022 this prop is an angle: use deg (e.g. 45.deg), not ms".}
