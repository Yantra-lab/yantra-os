# nimav

Video in and out for Yantra through **FFmpeg's libraries** (libavformat, libavcodec,
libswscale, libavutil — LGPL/GPL per the FFmpeg build; MSYS2 `mingw-w64-x86_64-ffmpeg`,
H.264 through libx264). The libraries are linked; the `ffmpeg` program is not used.

Today: encode BGRA frames from the engine straight to .mp4/.mov/.mkv/.webm, and probe a
video file (frames, size, duration, codec). Next: decode a video into frames the engine
draws as a layer (roadmap §4, pixel content in films).

Tests: `bash libs/nimav/tests/run_tests.sh` — writes a one-second H.264 clip and reads it
back with FFmpeg's own demuxer (30 frames, 64x48, h264, 1.0 s).
