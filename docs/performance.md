# Performance Baseline (M0-06)

This is the M0 performance baseline required by ROADMAP.md section 16.1 and
task M0-06. It establishes a reproducible starting point — **it is not an
optimization pass**, and several numbers here already miss the 1.0 targets
in section 16.1 on purpose: M0's job is to surface that gap honestly, not
to close it.

## Environment

| Field | Value |
|---|---|
| Date | 2026-08-04 |
| Commit | `e8f097e66a26a5398fffbe5b9f4c452097662632` (M0-01/02/03 batch; no `Sources/` changes since) |
| Hardware | MacBook Air, Mac14,2, Apple M2, 8 cores (4P+4E), 16 GB RAM — matches the ROADMAP §16.1 reference machine |
| OS | macOS 26.5.2 (build 25F84) |
| Build configuration | `swift build -c release` via `bash build.sh` (single-arch, host `arm64`) |
| Swift tools version | 5.9 |

## Method

Scripts: `scripts/benchmark-launch.sh` and `scripts/benchmark-open-file.sh`.

Both scripts launch the real `MaruEdit.app` bundle via `open -n` (the same
path a Finder/Dock double-click takes) and detect "settled" as the
process's CPU usage dropping below 5% for 3 consecutive 20ms samples —
i.e. it has finished its startup burst and returned to an idle run loop.
This is a **CPU-idle heuristic sampled from outside the process via `ps`**,
not an instrumented in-app timestamp (the app has no launch-time telemetry
yet). Treat absolute numbers as approximate and expect run-to-run system
noise; the methodology itself, not any single number, is what future
measurements should stay comparable to.

File-open fixtures are synthetic, generated fresh into a temp directory by
`benchmark-open-file.sh` on every run (repeated lines of the form
`func handler_NNNNNN(input: String) -> Int { ... }`) and never committed —
this guarantees they contain no sensitive data. They use a `.swift`
extension so `Document` detects them as Swift source and runs the normal
syntax-highlighting path, matching a realistic "open a large source file"
scenario.

## Results

| Metric | 1.0 target (§16.1) | Measured | Notes |
|---|---:|---:|---|
| Release app bundle size | ≤ 15 MB | **692 KB** | `du -sh MaruEdit.app`; binary itself is 556,648 bytes |
| Cold launch, median (n=7) | ≤ 300 ms | **232 ms** (min 212, max 716) | Bimodal: alternating fast (~220ms) / slow (~700ms) runs observed — not yet root-caused, see Known Risks below |
| Idle RSS, one window (n=7) | ≤ 80 MB | **~111 MB** | Consistent across runs (110.5–110.9 MB) — already over target |
| Open 1 MB `.swift` file to editable, median (n=5) | ≤ 200 ms | **2,235 ms** (min 2,139, max 2,268) | ~11x over target |
| Open 10 MB `.swift` file to editable, median (n=5) | ≤ 1,000 ms | **12,680 ms** (min 11,762, max 29,530) | ~13x over target; one run spiked to 29.5s |

## Analysis (original M0 baseline)

The file-open numbers are consistent with the risk ROADMAP.md already
flags in §5.3 and §16.3: **synchronous, main-thread, regex-based syntax
highlighting on the entire file** is the most likely cause — `Document`
detects `.swift` and the highlighter has no large-file degradation path
yet (§16.2's "Reduced Features Mode" doesn't exist yet; that's future
milestone work, not M0). This baseline is what later milestones' large-file
work (§16) should be measured against — no code changes were made to chase
these numbers down in the M0 batch, per M0-06's explicit "do not optimize
yet."

M5-05 subsequently replaced this synchronous whole-file path with the
revision-aware `SyntaxHighlightCoordinator`: matching is debounced and runs on
a background queue, viewport work is context-bounded, and regex highlighting
is disabled above 100,000 UTF-16 units. The M0 figures remain recorded here as
historical baseline data; they must not be presented as current measurements.

## Known Risks / Follow-Up

- Cold-launch bimodality (fast/slow alternating) is unexplained. Possible
  causes not yet investigated: window-server/launchd contention from the
  previous run's teardown, Gatekeeper re-verification of the unsigned
  binary, or Spotlight/quarantine re-checks. Needs investigation before
  M7's performance work, not blocking for M0.
- The CPU-idle heuristic is approximate; a proper fix is an in-app
  instrumented timestamp (e.g. log time-to-first-window-visible) once
  there's a logging facility (see `Sources/MaruEditCore/Utilities/Logger.swift`
  in the target structure, not yet created).
- Idle RSS and the M0 file-open measurements exceed 1.0 targets. M5-05 removes
  the identified synchronous highlighting bottleneck, but M7 must rerun the
  end-to-end scripts before claiming the launch/open targets are met.

## Reproducing

```bash
bash build.sh
bash scripts/benchmark-launch.sh 7
bash scripts/benchmark-open-file.sh 5
```
