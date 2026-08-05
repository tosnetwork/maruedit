#!/bin/bash
# Measures settled RSS after opening ten synthetic 1 MB documents.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
APP="MaruEdit.app"
EXE_PATH="$(pwd)/${APP}/Contents/MacOS/MaruEdit"
FIXTURE_DIR="$(mktemp -d)"
EVENT_FILE="${FIXTURE_DIR}/benchmark.events"
APP_PID=""
cleanup() {
  if [ -n "$APP_PID" ]; then kill "$APP_PID" 2>/dev/null || true; fi
  rm -rf "$FIXTURE_DIR"
}
trap cleanup EXIT

if [ ! -x "$EXE_PATH" ]; then
  echo "✗ ${EXE_PATH} not found. Run: bash build.sh" >&2
  exit 1
fi

python3 - "$FIXTURE_DIR" <<'PY'
import os, sys
root = sys.argv[1]
line = "synthetic multi-document fixture line 0123456789\n"
for index in range(10):
    path = os.path.join(root, f"fixture-{index}.txt")
    with open(path, "w", encoding="utf-8") as stream:
        while stream.tell() < 1_000_000:
            stream.write(line)
PY

open -n "$APP" --args --maruedit-benchmark-events "$EVENT_FILE"
for _ in $(seq 1 600); do
  APP_PID=$(awk -F '\t' '$1 == "launch-ready" { print $3; exit }' "$EVENT_FILE" 2>/dev/null || true)
  if [ -n "$APP_PID" ]; then break; fi
  sleep 0.01
done
if [ -z "$APP_PID" ]; then echo "app did not start" >&2; exit 1; fi

expected=0
for file in "$FIXTURE_DIR"/*.txt; do
  expected=$((expected + 1))
  printf 'open-request\t%s\n' "$file" >> "$EVENT_FILE"
  for _ in $(seq 1 1200); do
    observed=$(awk -F '\t' '$1 == "file-open-ready" { count++ } END { print count + 0 }' "$EVENT_FILE")
    if [ "$observed" -ge "$expected" ]; then break; fi
    sleep 0.01
  done
  if [ "${observed:-0}" -lt "$expected" ]; then
    echo "document ${expected} did not become editable" >&2
    exit 1
  fi
done

sleep 0.25
rss_kb=$(ps -o rss= -p "$APP_PID" | tr -d ' ')
echo "Multi-document RSS (10 x 1 MB): $(awk -v r="$rss_kb" 'BEGIN{printf "%.1f", r/1024}') MB (${rss_kb} KB)"
vmmap -summary "$APP_PID" 2>/dev/null | awk '/^Physical footprint:/ { print "Multi-document physical footprint: " $3; exit }'
