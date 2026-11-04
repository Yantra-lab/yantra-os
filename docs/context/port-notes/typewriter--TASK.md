# TASK: Carriage Return — A Typewriter for Letters (Marlowe 44)

## Objective
Port `029-typewriter-letters.html` and `029-typewriter-letters.txt` into a complete, 1:1 running Yantra native app in `apps/typewriter/app.nim`, compile it to `apps/typewriter/app.wasm` using `bash tools/build-wasm.sh apps/typewriter/app.nim apps/typewriter/app.wasm`, and verify with the native Yantra runner `render/native/build/desktop/yantra_run.exe`.

## Key Specifications & Requirements
1. **Visual fidelity & 1:1 recreation**:
   - Marlowe 44 typewriter in mint-green enamel (#9fc9b6), darker 3/4 cheek, top deck with ribbon spools, chrome details, script badge "Marlowe 44".
   - Procedural walnut desk with grain lines, knots, seams, warm lamplight radial gradient, bloom, and dried coffee ring.
   - Floating dust motes animated in the light beam.
   - Paper bail, platen roller, margin scale (0-48 with ticks and numbers), red bell marker at col 42, red column pointer.
   - Carriage assembly moves horizontally as typing advances.
   - Return lever swings on carriage return; carriage slides back smoothly with line feed.
   - Dual-color ribbon vibrator (black / red).
   - Side props: Operator instruction card, yellow pencil with eraser, shipping tag tracking sheet number, line, column, keystrokes.
   - Header controls: "Carriage Return" label badge, ribbon toggle (Black/Red), sound toggle, New Sheet, Save Letter.
   - Toast notifications for margin lock, sheet full, new sheet.

2. **Typing & Mechanics**:
   - Physical keyboard typing via `onKey:` on app root: printable characters, Space, Backspace (overstrikes without erasing), Tab (jumps to next multiple of 5), Return (swings lever, slides carriage, line feed).
   - On-screen clickable keys for all 4 rows + spacebar + carriage return lever.
   - Shift and Shift Lock with visual indicators and shifted characters.
   - Typewriter character stamping with realistic imperfections: baseline jitter, rotation jitter, ink density variations, ribbon weave knockout, faint double strikes.
   - Margin bell rings 6 columns before margin (col 42) with floating "ding" effect.
   - Margin lock at column 48.
   - New sheet animation and reset.
   - Initial pre-typed letter with date and salutation.
   - Session persistence for strokes, position, and sheet count.

3. **Build & Verification**:
   - Target binary: `apps/typewriter/app.wasm`
   - Build command: `bash tools/build-wasm.sh apps/typewriter/app.nim apps/typewriter/app.wasm`
   - Runner: `render/native/build/desktop/yantra_run.exe`
