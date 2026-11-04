# nimyoga

Clean, idiomatic Nim wrapper for Meta's Yoga flexbox layout engine (MIT).
Powers native UI layout in Yantra.

## Vendor Details
- Upstream: [facebook/yoga](https://github.com/facebook/yoga)
- Version: 3.1.0
- License: MIT
- Purpose: Flexbox layout calculation for Yantra native render target.
- Build: Pinned and fetched in tools/setup.sh; built as static libyoga.a.

## Building and Testing
Run tests via `bash libs/nimyoga/tests/run_tests.sh`.
Sources are pinned to Yoga v3.1.0 via `tools/setup.sh`.
