# nimrtc INTERFACE
- `newCall*(offerer: bool; iceServers = ""): Call`, `close*`
- `setRemote*(c, typ, sdp)`, `addCandidate*(c, cand, mid)`, `nextEvent*(c): string` (signaling out), `state*`
- `sendOpus*(c, data, n, samples)`, `nextPacket*(c, outp): int` (Opus payloads in)
- `playPush*(c, stereo, frames)`, `playPull*(): pointer` + `handle*(c)` (an audio device source)
