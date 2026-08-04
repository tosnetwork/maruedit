# Search and Grep

## Find and Replace

Open Find with Command-F. Literal and regular-expression modes share the same
search engine. Options include case sensitivity, whole word, wrap, and
selection-only scope. Find Next/Previous update the editor selection and match
count. Replace One validates the current match; Replace All is one undoable
edit and handles zero-length regular-expression matches without looping.

Regex replacement supports capture references. An invalid expression is shown
as a recoverable validation error and does not modify the document.

## Folder Grep

Folder Grep searches a selected directory off the main thread and streams
results to the result view. Results contain file, line, column, and preview;
activating one opens the file at the match. Hidden/package/symlink policy and
binary/encoding handling are explicit, and the scan can be cancelled at any
time. Cancellation retains already-delivered results and reports a cancelled
summary rather than pretending the scan completed.

## Grep Replace

Grep Replace has a mandatory preview. Review included files and replacements,
then apply. Files are written atomically with their encoding, BOM, and line
ending policy preserved. Open modified documents participate in external-file
conflict handling. The operation reports partial failures per file; it never
claims an all-or-nothing transaction across a directory.

For implementation guarantees and failure behavior, see
[Grep Replace](grep-replace.md).
