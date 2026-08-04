# Memory and Buffer Audit

This document records the M7-02 ownership audit. Measurements are from an
Apple M2 MacBook Air with 16 GB RAM on macOS 26.5.2, Release configuration,
2026-08-05.

## Buffer lifecycle

1. `TextFileLoader` maps the file with `Data(contentsOf:options:.mappedIfSafe)`.
   The mapped `Data` is a local value and is not a field of `LoadedText`.
2. `EncodingDetector` produces the decoded `String`. `LoadedText` returns that
   string plus small metadata only. The mapped bytes leave scope when loading
   returns and can be unmapped; the editor never retains the original bytes.
3. `Document.open` normalizes line endings into its editing `String`. A clean
   document's `content` and `savedContent` initially share Swift copy-on-write
   storage. The decoded pre-normalization string leaves scope after open.
4. On first display, `EditorViewController` creates one `NSTextStorage` and
   caches it on the `Document` so tab switches reuse it. No second text storage
   is created for the same document. `LineIndex` stores integer line offsets
   and deliberately retains no copy of the string.
5. Saving creates line-ending-converted `String` and encoded `Data` as local
   temporaries. They are released when `save()` returns.

Session persistence contains paths, cursor offsets, and window state, never
document content. Recovery accepts a value snapshot, encodes it immediately,
and retains neither the `RecoveryRecord` nor encoded `Data` after `save`
returns. Loading similarly returns decoded records without caching source
`Data`. The debounced App closure captures the `Document` weakly and constructs
the record only when the write begins, avoiding a second large string retained
during the debounce interval.

## Measurements

`MemoryAuditTests.testTenOpenTenMegabyteDocumentsRemainEditable` creates ten
independent 10 MiB files, opens all ten, materializes one `NSTextStorage` per
document, edits every buffer, and reports process resident-size delta. The
fixture is generated in a temporary directory and removed after the test.

| Measurement | Before | After |
|---|---:|---:|
| Ten open/editable 10 MiB documents, current RSS | 31.69 MiB | 291.08 MiB (+259.39 MiB) |

The M0 baseline did not include this ten-document scenario, so “before” here
means immediately before opening the ten documents in the same test process;
“after” means after all ten text storages exist and have accepted an edit.

## Instruments procedure

The SwiftPM Release executable is linker-signed. Instruments requires an
attachable development signature, so the disposable build artifact (not any
source or release product) was ad-hoc re-signed with
`com.apple.security.get-task-allow=true`, then both templates were recorded:

```bash
xcrun xctrace record --template Allocations --time-limit 5s \
  --output /tmp/maruedit-m7-02-allocations-signed.trace \
  --launch -- .build/release/MaruEditApp
xcrun xctrace record --template Leaks --time-limit 8s \
  --output /tmp/maruedit-m7-02-leaks-signed.trace \
  --launch -- .build/release/MaruEditApp
```

Both recordings completed and their exported tables of contents identify the
MaruEdit PID and the expected Allocations and Leaks tracks. Allocations sampled
for 5.69 seconds and Leaks for 8.70 seconds. A follow-up `vmmap -summary` at idle
reported a 59.8 MiB physical footprint (82.2 MiB peak), with 9.8 MiB allocated
in malloc zones. The command-line `leaks --list` cross-check reported 282 small
live allocations totaling 14,128 bytes; none of the listed leak entries carried
a MaruEdit-owned stack (they were macOS framework/process-lifetime state). No
project-code retain cycle was identified. The raw traces remain in `/tmp` and
are intentionally not committed.
