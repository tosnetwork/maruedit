#!/bin/bash
# File-open baseline (1 MB / 10 MB UTF-8 text) for ROADMAP.md task M0-06.
#
# Fixtures are synthetic (generated fresh each run, never committed) so
# they can never contain sensitive data.
#
# Method: for each run, launch a fresh MaruEdit.app instance via `open -n`,
# then send the fixture through a benchmark-only local command channel. An
# opt-in application probe records
# when the document is installed and its first view is editable. Deferred
# highlighting is intentionally excluded from this user-visible readiness gate.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

APP="MaruEdit.app"
EXE_PATH="$(pwd)/${APP}/Contents/MacOS/MaruEdit"
RUNS="${1:-5}"
FIXTURE_DIR="$(mktemp -d)"
trap 'rm -rf "$FIXTURE_DIR"' EXIT

if [ ! -x "$EXE_PATH" ]; then
  echo "✗ ${EXE_PATH} not found. Run: bash build.sh" >&2
  exit 1
fi

make_fixture() {
  local path="$1" target_bytes="$2"
  python3 - "$path" "$target_bytes" <<'PY'
import sys
path, target_bytes = sys.argv[1], int(sys.argv[2])
line = "func handler_{n:06d}(input: String) -> Int {{ return input.count + {n} }} // synthetic fixture line, no real data\n"
with open(path, "w", encoding="utf-8") as f:
    n = 0
    written = 0
    while written < target_bytes:
        s = line.format(n=n)
        f.write(s)
        written += len(s.encode("utf-8"))
        n += 1
PY
}

FIXTURE_1MB="${FIXTURE_DIR}/fixture-1mb.swift"
FIXTURE_10MB="${FIXTURE_DIR}/fixture-10mb.swift"
make_fixture "$FIXTURE_1MB" $((1 * 1000 * 1000))
make_fixture "$FIXTURE_10MB" $((10 * 1000 * 1000))
echo "Fixtures: $(du -h "$FIXTURE_1MB" | cut -f1) / $(du -h "$FIXTURE_10MB" | cut -f1)"

wait_event() {
  local event_file="$1" event="$2" detail="$3" timeout_iters="$4" not_before="${5:-0}"
  local timestamp=""
  for _ in $(seq 1 "$timeout_iters"); do
    timestamp=$(awk -F '\t' -v event="$event" -v detail="$detail" -v not_before="$not_before" \
      '$1 == event && $2 >= not_before && (detail == "" || $3 == detail) { print $2; exit }' \
      "$event_file" 2>/dev/null || true)
    if [ -n "$timestamp" ]; then echo "$timestamp"; return 0; fi
    sleep 0.01
  done
  return 1
}

bench_fixture() {
  local fixture="$1" label="$2"
  local times=()
  echo ""
  echo "== ${label} =="
  for i in $(seq 1 "$RUNS"); do
    event_file="${FIXTURE_DIR}/${label// /-}-${i}.events"
    open -n "$APP" --args --maruedit-benchmark-events "$event_file"
    if ! wait_event "$event_file" "launch-ready" "" 600 >/dev/null; then
      echo "  run $i: initial editable-ready event not observed" >&2
      continue
    fi
    pid=$(awk -F '\t' '$1 == "launch-ready" { print $3; exit }' "$event_file")
    if [ -z "$pid" ]; then
      echo "  run $i: benchmark PID not observed, discarding" >&2
      continue
    fi

    start=$(python3 -c 'import time; print(time.time())')
    printf 'open-request\t%s\n' "$fixture" >> "$event_file"
    if ready=$(wait_event "$event_file" "file-open-ready" "" 1200 "$start"); then
      ms=$(python3 -c "print(f'{(${ready} - ${start}) * 1000:.1f}')")
      times+=("$ms")
      echo "  run $i: ${ms} ms"
    else
      echo "  run $i: file editable-ready event not observed, discarding" >&2
    fi

    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    sleep 0.3
  done

  python3 - "${times[@]}" <<'PY'
import sys, statistics
times = [float(x) for x in sys.argv[1:]]
if times:
    print(f"{statistics.median(times):.1f} ms median (min={min(times):.1f} max={max(times):.1f} n={len(times)})")
else:
    print("No successful runs.")
PY
}

bench_fixture "$FIXTURE_1MB" "1 MB UTF-8"
bench_fixture "$FIXTURE_10MB" "10 MB UTF-8"
