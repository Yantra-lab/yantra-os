# 11. Sound

Sound plays, is made, and is mixed through the same engine as pictures, on the same
clock.

## 11.1 What exists

- Sound assets are kept in Postgres and played by the engine (`yantra/engine.nim`).
  **built**
- The protocol has `Audio` (a sound to play, with volume, rate, loop) and `Synth` (a sound
  made by the engine, with a filter: low-pass, high-pass, band-pass) nodes
  (`protocol/schema.nim`).
- miniaudio is wrapped (`libs/nimminiaudio`) for playing and recording; FFmpeg
  (`libs/nimffmpeg`, `libs/nimav`) for reading and writing sound in every format.

## 11.2 Planned

- **A sound graph:** oscillators, samples, filters, envelopes, delays and mixers as nodes,
  connected and changed live, the way a view's tree is:

```text
sound Pad
  param cutoff = 1200 in 200 .. 8000
  let tone = saw(220) + saw(220.5)
  out lowpass(tone, cutoff) * envelope(attack = 2s, release = 4s)
```

- **On the timeline:** sound placed in a film or a game by time, with the exact clock of
  §10.2, so a cut and its sound never drift.
- **Voices, music and sound effects from models** (§12): `voice(...)`, `music(...)`,
  `sound(...)`.
- **Speech to text** for captions (§22.2) and for talking to an agent (§19).

## 11.3 Tests

Planned (each one is a task):
- `Pad` rendered to a file twice gives the same samples.
- Moving `cutoff` changes the sound within one audio buffer, with no click.
- In a film, a sound placed at 2.000 s starts at sample 2.000 × the sample rate.
