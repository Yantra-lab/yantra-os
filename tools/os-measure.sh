#!/usr/bin/env bash
# tools/os-measure.sh — every number in README.md comes from here.
#
#   bash tools/os-measure.sh            print the measured app table
#   bash tools/os-measure.sh --write    rewrite the README block from the tree
#   bash tools/os-measure.sh --check    fail if the README block is stale
#   bash tools/os-measure.sh --json     machine-readable
#
# The measuring is done by tools/os-measure.mjs; this wrapper exists so the
# command in the README and in CI is a plain shell command.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec node "$HERE/os-measure.mjs" "$@"
