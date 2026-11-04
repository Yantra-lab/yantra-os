# yantra-os — the open release

This folder is **the public release tree** of Yantra: the exact contents published to
`Yantra-lab/yantra-os` for the Meta Developer Hackathon (Startups track) and beyond.

- **Source of truth:** the private repo this folder lives in. Never edit the published repo
  directly; edit here, then publish.
- **Publish:** `bash tools/publish-os.sh` (subtree push from the repo root).
- **Contents:** the showcase apps (`apps/`), the engine subset judges need to read and
  rebuild (`host/ libs/ sdk/ protocol/ render/`), the docs, and prebuilt `.wasm` binaries so
  verification runs keyless and instantly (`node tools/verify-wasm.mjs apps/<name>`).
- **Junk policy:** no scratch debris, no duplicate context dumps at the top level — AI
  context lives in `docs/context/`.

## The bar for anything here

1. Every number in `README.md` is measured, never estimated.
2. Every app builds from source with `tools/build-wasm.sh` and passes the headless verifier.
3. Every app is a *proof of the language*: short, typed, gorgeous — not a hand-carved port.
4. A judge with no keys, no GPU, no setup can verify everything in under a minute.
