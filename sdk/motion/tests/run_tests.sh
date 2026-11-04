#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")"

echo "== verify motion timeline tests =="
if ! nim c --path:.. -r t_timeline.nim; then
  echo "FAIL t_timeline"
  exit 1
fi
echo "PASS t_timeline"
rm -f t_timeline.exe
