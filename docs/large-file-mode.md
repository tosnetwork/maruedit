# Large-File Mode

MaruEdit inspects regular-file metadata before reading or decoding content.
Thresholds are centralized in `LargeFilePolicy` and are engineering defaults,
not product promises:

| File size | Behavior |
|---:|---|
| Below 1 MiB | Normal Mode |
| 1 MiB to below 10 MiB | Open automatically in Reduced Features Mode |
| 10 MiB through 256 MiB | Ask: Continue Reduced, Open Read-Only, or Cancel |
| Above 256 MiB | Refuse before materializing bytes |

The thresholds follow the M0 reference benchmark: 1 MB took 2,235 ms against a
200 ms target and 10 MB took 12,680 ms against a 1 s target. Later highlighting
work improves those figures, but the 1.0 safety policy stays conservative until
M7-08 reruns the same end-to-end benchmark and provides retuning evidence.

Reduced Features Mode disables syntax highlighting, line wrapping, and
invisible-character drawing, and limits Undo to 20 operations. The orange
status-bar indicator communicates the mode without relying on color alone.
Clicking it offers an explicit, warned “Enable All Features” action for the
current document. Read-only mode uses the same reductions and also makes the
text view non-editable.

The 256 MiB ceiling prevents an ordinary `Data` → `String` → `NSTextStorage`
open from causing an unbounded allocation. A sparse-file test verifies refusal
happens from metadata before the loader runs. Reopen-with-encoding repeats the
same preflight.

Streaming Read-Only is deliberately not implemented in the ordinary Document
or TextKit path. A credible implementation needs a separate mapped/chunked
buffer, search/navigation contracts, and benchmarks. Shipping a materialized
buffer under a “streaming” label would hide rather than solve the allocation
risk, so this remains an isolated post-1.0 experiment.

All new alerts, buttons, status text, tooltips, and accessibility labels have
English, Japanese, and Simplified Chinese strings.
