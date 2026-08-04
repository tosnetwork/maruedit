# Macro Engine Foundation

MaruEdit macros run in JavaScriptCore with API version `maru.apiVersion === 1`.
Every run creates a new virtual machine and context, so globals and JavaScript
objects cannot leak into another run. The context exposes no application,
document, filesystem, network, or arbitrary Objective-C object. Capabilities are
introduced only as narrow functions on the frozen `maru` object.

M6-01 provides deterministic pure text helpers:

- `maru.text.uppercase(string)`
- `maru.text.lowercase(string)`
- `maru.text.trim(string)`
- `maru.text.normalizeLineEndings(string)`

When the application supplies an active-editor host, the M6-02 command,
document, editor, clipboard, UI, and Undo capabilities described in
`macro-api-v1.md` are added. The engine retains the bridge for the complete
run, while every AppKit operation is marshalled to the main thread.

JavaScript failures report their message, stack, line, and column when supplied
by JavaScriptCore. Runs execute on a dedicated background queue by default.

## Cancellation and timeout contract

Cancellation and the deadline are checked before execution, at entry and exit
of every Maru host API, through `maru.checkCancellation()`, and after the script
returns. A cancelled run reports `MacroExecutionError.cancelled`; a deadline
reports `.timedOut`, and its result is discarded.

JavaScriptCore's public in-process macOS API does not provide a safe way to
preempt a pure-JavaScript infinite loop. Consequently, M6-01 cancellation is
cooperative: scripts doing long pure-JavaScript work must call
`maru.checkCancellation()`. Hard termination would require running macros in a
separate helper process; callers must not describe this foundation as a sandbox
against CPU denial of service.
