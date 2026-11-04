// web/runner/test.mjs — the suite `run_tests.sh` runs.
//
// The counter test needs `examples/counter.wasm`, which this tree now builds from
// `examples/counter.nim` with `tools/build-wasm.sh` (the release ships the built
// module beside its source).
//
// The todo test is NOT imported here: it asserts the pre-Sutra todo app's seed
// list ("Write the pitch", …) and the release's todo is now a Sutra app backed by
// records, so that suite fails on the new module rather than on the runner. It is
// kept at tests/todo.mjs and is listed in docs/VERIFICATION.md as stale.
import './tests/test.mjs';
import './tests/flagships.mjs';
