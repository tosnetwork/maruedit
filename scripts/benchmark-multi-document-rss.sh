#!/bin/bash
# Measures settled RSS after opening ten synthetic 1 MB documents.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
APP="MaruEdit.app"
EXE_PATH="$(pwd)/${APP}/Contents/MacOS/MaruEdit"
FIXTURE_DIR="$(mktemp -d)"
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

open -n "$APP"
for _ in $(seq 1 200); do
  APP_PID=$(LC_ALL=C pgrep -f "$EXE_PATH" | head -1 || true)
  if [ -n "$APP_PID" ]; then break; fi
  sleep 0.01
done
if [ -z "$APP_PID" ]; then echo "app did not start" >&2; exit 1; fi

for file in "$FIXTURE_DIR"/*.txt; do open -a "$APP" "$file"; done

low_count=0
for _ in $(seq 1 1000); do
  sleep 0.02
  cpu=$(ps -o %cpu= -p "$APP_PID" 2>/dev/null | tr -d ' ')
  if [ -z "$cpu" ]; then echo "app exited" >&2; exit 1; fi
  if awk -v c="$cpu" 'BEGIN{exit !(c<5)}'; then
    low_count=$((low_count + 1))
  else
    low_count=0
  fi
  if [ "$low_count" -ge 5 ]; then break; fi
done

rss_kb=$(ps -o rss= -p "$APP_PID" | tr -d ' ')
echo "Multi-document RSS (10 x 1 MB): $(awk -v r="$rss_kb" 'BEGIN{printf "%.1f", r/1024}') MB (${rss_kb} KB)"
