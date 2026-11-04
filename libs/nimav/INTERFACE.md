# nimav — interface

```nim
var enc = openEncoder("out.mp4", width = 1920, height = 1080, fps = 60, crf = 18)
enc.addFrame(pixels, strideBytes)      # BGRA, top row first
enc.close()                            # must be called; the file is playable after
let info = probe("out.mp4")            # VideoInfo(frames, width, height, seconds, codec)
```

Errors raise `AvError`. One encoder thread, so the same frames give the same file.
