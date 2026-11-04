# nimaccesskit

Screen readers for Yantra through [AccessKit](https://github.com/AccessKit/accesskit-c)
(MIT/Apache-2.0), built from source: `cd third_party/accesskit-c && cargo build --release`
(render/native/run_tests.sh does it when the DLL is missing). Windows UI Automation today;
AccessKit's macOS and AT-SPI adapters use the same snapshot later.

The engine publishes snapshots of its tree (ak_shim.c keeps them under a lock, because screen
readers ask on their own threads) and takes the actions they request from a queue.
Tests: render/native/t_a11y.nim (headless) and t_a11y.ps1 (a real window through UI Automation).
