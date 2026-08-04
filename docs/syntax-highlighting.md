# Syntax Highlighting

`SyntaxHighlightCoordinator` separates editor events from regex matching. The
editor gives it an immutable text snapshot, language, font, and either a
viewport or an explicit whole-document request. Requests are debounced; regex
matching runs on a serial user-initiated worker queue, while `NSTextStorage`
attributes are applied on the main queue.

Every request advances a lock-protected document revision. The coordinator
checks that revision before matching and again before applying attributes. It
also compares the live storage string with the snapshot. A result therefore
cannot color a newer edit even when cancellation races with work already in a
queue.

Viewport requests include 3,000 UTF-16 units of surrounding context and expand
to whole-line boundaries. This prevents unstyled edges while keeping ordinary
typing and scrolling work bounded. Initial loads and explicit theme refreshes
may request a complete small document. Files above 100,000 UTF-16 units enter
large-file mode automatically: stale syntax colors are reset to the base
foreground color, and no regex work is scheduled.

Syntax rules compile independently. An invalid regular expression is skipped,
leaving all valid rules active. Highlight and theme refresh operations change
font/foreground attributes only; they never replace characters.

## Benchmark

`SyntaxHighlightCoordinatorTests.testPerformanceHighlightingRequiredViewportContext`
uses XCTest's wall-clock performance measurement with the production Swift
grammar and a synthetic 2,000-line source document. It deliberately measures
the buffered viewport context rather than a whole large file, matching the
interactive path. This microbenchmark detects grammar or range regressions;
M7 remains responsible for repeating the real application launch and file-open
benchmarks documented in `performance.md`.
