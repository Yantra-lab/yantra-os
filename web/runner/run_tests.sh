#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "== web runner tests =="
if node "$HERE/test.mjs"; then
  echo "PASS web_runner"
else
  echo "FAIL web_runner"
  exit 1
fi
