# User Guide

## Open and save

Use **File > Open** for one file or **Open Folder** for a project tree. Tabs in
one window and separate windows own independent documents. Save writes through
an atomic replacement so a failed write does not truncate the original.
Unsaved recovery data is separate from the source file and never overwrites it
automatically.

If another process changes, replaces, moves, or deletes an open file, MaruEdit
asks how to resolve the conflict instead of silently overwriting it. Compare
the in-memory work with disk before choosing reload or overwrite.

## Encodings and BOMs

MaruEdit detects UTF-8/16/32 and supported Japanese legacy encodings when a
file is opened. The status bar shows the active encoding. Use the document
encoding controls to reopen with an explicit encoding or choose the encoding
used by Save As. A BOM is tracked separately where the format supports it, so
opening and saving can preserve the original byte convention.

Changing the decoding of modified text is intentionally guarded: save or
discard edits first. When detection is ambiguous, inspect the preview before
committing to a legacy encoding.

## Line endings

LF, CRLF, and CR are detected independently of encoding. Mixed files retain a
mixed state until saving requires a choice. Choose the desired line ending in
the status/document controls; the text model uses normalized newlines while
the saver writes the selected byte representation.

## Large files

Files at or above 10 MiB require confirmation and use reduced, read-only mode;
files above 256 MiB are refused. Accepted large reads run on the file-I/O
queue, and an opening status is shown. See [Large-file mode](large-file-mode.md)
for the exact limits and tradeoffs.

## Settings and profiles

Settings cover appearance, editing, key bindings, file-type profiles, macros,
and external commands. File-type profiles can select encoding, line ending,
syntax, and display defaults by extension without changing unrelated files.
See [Settings](settings.md) and [File-type profiles](file-type-profiles.md).

## Help and network access

MaruEdit Help, Macro Help, and the keyboard reference open the bundled
`maruedit.pdf` manual locally. They do not require an internet connection.
Commands whose names say **Online**, and external-help entries configured with
an HTTP(S) URL, show the destination and ask before opening the default browser.
Cancelling performs no network-facing action. Local external-help files open
without that prompt.
