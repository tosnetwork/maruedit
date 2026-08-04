# Grep Replace Preview

Choose **Find > Find in Folder**, enter Find and Replace values, then choose **Preview Replace…**. MaruEdit scans without modifying files and opens a grouped preview. Every file and match starts selected; either level can be excluded. Selecting a row shows the complete normalized before/after text.

Applying the preview runs off the UI thread. Immediately before each write, MaruEdit compares the complete current byte sequence with the sequence captured by the scan. A changed, moved, deleted, or otherwise different file is reported as a conflict and is not overwritten. Text must remain representable in its detected encoding. Existing BOM, single-style line endings, and POSIX permissions are preserved.

For each selected file, the original bytes are copied into a unique transaction directory. An atomic `transaction.json` mapping original paths to backups is updated before the destination is atomically replaced. The shared Output Pane reports the recovery directory, successes, conflicts, encoding failures, write failures, cancellation, and partial completion.

Stopping during the scan produces no preview and performs no writes. Stopping during application preserves completed files and their recovery records, marks every remaining selected file cancelled, and reports the partial result.
