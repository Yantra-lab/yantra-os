# nimrtc

Voice calls over WebRTC for Yantra (Q11), through [libdatachannel](https://github.com/paullouisageneau/libdatachannel)
(MPL-2.0; MSYS2 `mingw-w64-x86_64-libdatachannel`, bundling libjuice for ICE and usrsctp/libsrtp). One peer
connection with one Opus track. The engine encodes the microphone with libav's Opus encoder (nimav) and plays
what arrives through the shared miniaudio device.
