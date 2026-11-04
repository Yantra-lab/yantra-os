# nimcurl

HTTP for Yantra through [libcurl](https://curl.se/libcurl/), from the MSYS2 toolchain
(`pacman -S mingw-w64-x86_64-curl` in `third_party/msys64`). Licence: curl (MIT-style).

Many requests run at once on the caller's own thread through libcurl's multi interface,
so the engine starts requests and polls them each frame; nothing blocks and there are
no threads.

It is deliberately narrow:
- GET only.
- https only, unless the caller allows plain http (the engine does that only for this machine).
- Redirects are not followed, so a redirect can never lead somewhere unchecked.
- Bodies are capped (8 MB by default), and requests time out (30 s by default).
- Certificates come from the operating system's own store (`CURLSSLOPT_NATIVE_CA`).

Which hosts an app may reach is decided by the host (`host/host.nim` `netAllowed`), not here.

Tests: `bash tests/run_tests.sh` runs `t_curl.nim` against a small server on 127.0.0.1
(`tests/localserver.nim`), so they never touch the internet.
