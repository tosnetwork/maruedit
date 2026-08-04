#!/bin/bash
# Cold-launch and idle-memory baseline for ROADMAP.md task M0-06.
#
# Method: launches the real .app bundle via `open -n` (the same path a
# user double-clicking in Finder or Dock goes through), then finds the
# resulting process by matching its full executable path. "Launched" is
# detected as the process's CPU usage dropping below 5% for 3 consecutive
# 20ms samples, i.e. it has finished its startup burst and settled into
# the idle run loop. This is a heuristic, not an instrumented in-app
# timestamp — treat results as an engineering baseline, not a precise
# measurement, and expect some run-to-run system noise.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

APP="MaruEdit.app"
EXE_PATH="$(pwd)/${APP}/Contents/MacOS/MaruEdit"
RUNS="${1:-5}"

if [ ! -x "$EXE_PATH" ]; then
  echo "✗ ${EXE_PATH} not found. Run: bash build.sh" >&2
  exit 1
fi

launch_times=()
rss_values=()

for i in $(seq 1 "$RUNS"); do
  start=$(python3 -c 'import time; print(time.time())')
  open -n "$APP"

  pid=""
  for _ in $(seq 1 100); do
    pid=$(LC_ALL=C pgrep -f "$EXE_PATH" | head -1)
    if [ -n "$pid" ]; then break; fi
    sleep 0.01
  done

  low_count=0
  settled=0
  if [ -n "$pid" ]; then
    for _ in $(seq 1 300); do
      sleep 0.02
      cpu=$(ps -o %cpu= -p "$pid" 2>/dev/null | tr -d ' ')
      if [ -z "$cpu" ]; then break; fi
      if awk -v c="$cpu" 'BEGIN{exit !(c<5)}'; then
        low_count=$((low_count + 1))
      else
        low_count=0
      fi
      if [ "$low_count" -ge 3 ]; then
        settled=1
        break
      fi
    done
  fi

  end=$(python3 -c 'import time; print(time.time())')

  rss_kb=""
  if [ "$settled" -eq 1 ]; then
    sleep 0.05
    for _ in $(seq 1 3); do
      rss_kb=$(ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ')
      if [ -n "$rss_kb" ] && [ "$rss_kb" -gt 1000 ] 2>/dev/null; then break; fi
      sleep 0.05
    done
  fi

  if [ "$settled" -eq 0 ] || [ -z "$pid" ]; then
    echo "  run $i: did not settle within timeout, discarding" >&2
  else
    ms=$(python3 -c "print(f'{(${end} - ${start}) * 1000:.1f}')")
    launch_times+=("$ms")
    rss_values+=("${rss_kb:-0}")
    echo "  run $i: ${ms} ms, RSS ${rss_kb:-0} KB"
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

python3 - "${rss_values[@]}" <<'PY'
import sys, statistics
rss = [float(x) for x in sys.argv[1:] if float(x) > 0]
if rss:
    print(f"Idle RSS (MB): median={statistics.median(rss)/1024:.1f} min={min(rss)/1024:.1f} max={max(rss)/1024:.1f} n={len(rss)}")
PY
