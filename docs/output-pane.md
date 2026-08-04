# Shared Output Pane

Grep results, macro errors, and external-process stdout/stderr use the same bounded Output Pane. Grep matches retain their highlighted preview; skipped files appear as warnings. Process and macro records show `HH:mm:ss`, channel, severity, and message.

The toolbar provides Copy, Clear, Save, Stop (while work is running), and Close. Copy and Save include the complete visible buffer. Clear cancels an active Grep or process before discarding its output. Output is limited to 10,000 records and 4 MiB of UTF-8 message data; the oldest records are removed and a visible warning is inserted when either limit is reached.

Rows shaped like `path:line`, `path:line:column`, or either form followed by a message are navigable with double-click or Return. Relative paths emitted by an external command resolve against that command's working directory. Grep locations use the exact URL and range reported by the search engine.

Channels are `grep`, `macro`, `stdout`, `stderr`, and `system`. Stderr and macro failures use error severity; skipped files and truncation notices use warning severity.
