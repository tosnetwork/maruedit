# MaruEdit 1.0.0

MaruEdit 1.0 is an independent, native macOS text editor focused on predictable
file handling and familiar high-speed editing workflows.

Highlights include encoding/BOM/newline preservation, literal and regex
Find/Replace, folder Grep and previewed Grep Replace, BOX and multiple
selections, Japanese/Chinese IME support, configurable ordinary/chorded keys,
file-type profiles, controlled JavaScript macros, controlled external commands,
crash recovery, and external-change conflict handling.

Requirements: macOS 13 or later; Universal arm64 and x86_64 application.

Known limitations:

- Cold launch and idle RSS remain above their engineering targets on the M2
  reference system; see issues #1 and #3.
- macOS 13 deployment compatibility is compiled but cannot currently be run on
  GitHub-hosted CI because that image has been retired.
- Very large files use reduced read-only mode; see `docs/large-file-mode.md`.

Before installation, compare the downloaded DMG with the published SHA-256.
The final release must also pass `codesign`, Gatekeeper (`spctl`), and notarized
ticket (`stapler`) validation. MaruEdit is not affiliated with or endorsed by
the developers of OldMaru Editor; attribution is in NOTICE.md and UPSTREAM.md.
