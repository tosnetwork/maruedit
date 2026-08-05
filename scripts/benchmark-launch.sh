#!/bin/bash
# Cold-launch and idle-memory baseline for ROADMAP.md task M0-06.
#
# Method: launches the real .app bundle via `open -n` (the same path a
# user double-clicking in Finder or Dock goes through). A command-line-only
# probe records when the first window is editable. This avoids mistaking
# `ps` CPU-average decay or deferred background work for user-visible launch.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

APP="MaruEdit.app"
EXE_PATH="$(pwd)/${APP}/Contents/MacOS/MaruEdit"
RUNS="${1:-5}"
BENCHMARK_DIR="$(mktemp -d)"
trap 'rm -rf "$BENCHMARK_DIR"' EXIT

if [ ! -x "$EXE_PATH" ]; then
  echo "✗ ${EXE_PATH} not found. Run: bash build.sh" >&2
  exit 1
fi

launch_times=()
rss_values=()
footprint_values=()

for i in $(seq 1 "$RUNS"); do
  start=$(python3 -c 'import time; print(time.time())')
  event_file="${BENCHMARK_DIR}/launch-${i}.events"
  open -n "$APP" --args --maruedit-benchmark-events "$event_file"

  ready=""
  for _ in $(seq 1 600); do
    ready=$(awk -F '\t' '$1 == "launch-ready" { print $2; exit }' "$event_file" 2>/dev/null || true)
    if [ -n "$ready" ]; then break; fi
    sleep 0.01
  done
  pid=$(awk -F '\t' '$1 == "launch-ready" { print $3; exit }' "$event_file" 2>/dev/null || true)

  rss_kb=""
  if [ -n "$ready" ]; then
    # Let deferred menus/services finish before measuring idle memory. This
    # delay is not included in the launch-ready timestamp above.
    sleep 0.5
    for _ in $(seq 1 3); do
      rss_kb=$(ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ')
      if [ -n "$rss_kb" ] && [ "$rss_kb" -gt 1000 ] 2>/dev/null; then break; fi
      sleep 0.05
    done
  fi

  if [ -z "$ready" ] || [ -z "$pid" ] || [ -z "$rss_kb" ] || [ "$rss_kb" -le 1000 ] 2>/dev/null; then
    echo "  run $i: editable-ready event not observed, discarding" >&2
  else
    ms=$(python3 -c "print(f'{(${ready} - ${start}) * 1000:.1f}')")
    launch_times+=("$ms")
    rss_values+=("${rss_kb:-0}")
    footprint=$(vmmap -summary "$pid" 2>/dev/null \
      | awk '/^Physical footprint:/ { print $3; exit }')
    footprint_mb=$(python3 - "$footprint" <<'PY'
import sys
value = sys.argv[1].upper()
scale = 1.0
if value.endswith("K"): scale = 1 / 1024
elif value.endswith("G"): scale = 1024
number = float(value[:-1]) if value[-1:] in "KMG" else float(value)
print(f"{number * scale:.1f}")
PY
)
    footprint_values+=("$footprint_mb")
    echo "  run $i: ${ms} ms, RSS ${rss_kb:-0} KB, footprint ${footprint_mb} MB"
  fi

  if [ -n "$pid" ]; then
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
  sleep 0.3
done

python3 - "${launch_times[@]}" <<'PY'
import sys, statistics
times = [float(x) for x in sys.argv[1:]]
if times:
    print(f"\nLaunch time (ms): median={statistics.median(times):.1f} min={min(times):.1f} max={max(times):.1f} n={len(times)}")
else:
    print("\nNo successful runs.")
PY

python3 - "${footprint_values[@]}" <<'PY'
import sys, statistics
values = [float(x) for x in sys.argv[1:]]
if values:
    print(f"Physical footprint (MB): median={statistics.median(values):.1f} min={min(values):.1f} max={max(values):.1f} n={len(values)}")
PY

python3 - "${rss_values[@]}" <<'PY'
import sys, statistics
rss = [float(x) for x in sys.argv[1:] if float(x) > 1000]
if rss:
    print(f"Idle RSS (MB): median={statistics.median(rss)/1024:.1f} min={min(rss)/1024:.1f} max={max(rss)/1024:.1f} n={len(rss)}")
PY
