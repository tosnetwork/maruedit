# Experimental Maru Macro Compatibility

This feature is experimental, incomplete, and disabled by default. It is a clean-room implementation of the public behavior documented below; it does not contain or depend on Maru source code, binaries, private APIs, or copied help text. MaruEdit does not claim general Maru macro compatibility.

Enable it for one launch with `MARUEDIT_ENABLE_OLDMARU_COMPATIBILITY=1`, or set the `ExperimentalMaruMacroCompatibility` user default to `true`, then reload macros. UTF-8 `.mac` files in the normal MaruEdit Macros directory appear with “(Experimental)” in their menu title and a separate `macro.compat.*` command ID. When disabled, `.mac` files are ignored.

The parser accepts case-insensitive commands, semicolon-separated statements,
comments, quoted strings, numeric `#variables`, string `$variables`, guarded
expressions, brace-delimited `if`/`else` and `while`, named zero-argument
functions, `call`, `return`, `break`, and `continue`. Loops inject cooperative
cancellation checks. Unsupported input fails with a line-numbered diagnostic.

## Compatibility matrix

| Command | State | Documented MaruEdit behavior |
|---|---|---|
| `selectall;` | Compatible for documented cases | Select the complete current document. |
| `gofiletop;` | Compatible for documented cases | Move to UTF-16 offset zero. |
| `gofileend;` | Compatible for documented cases | Move to the current document end. |
| `insert "text";` | Compatible for documented cases | Replace every current selection with the string; place carets after inserts. |
| `delete;` | Compatible for documented cases | Delete every current selection. |
| `toupper;` | Compatible for documented cases | Uppercase each selected value independently and keep it selected. |
| `tolower;` | Compatible for documented cases | Lowercase each selected value independently and keep it selected. |
| `message "text";` | Compatible for documented cases | Display a non-file, non-process UI message. |
| Variables, expressions, `if`/`else`, `while` | Compatible for documented cases | Sandboxed values and cooperatively cancellable control flow. |
| `function name { ... }`, `call name`, `return` | Compatible for documented cases | Named zero-argument subroutines. |
| `findnext`, `findprevious`, `showoutline`, `nextwindow` | Native equivalent | Routed through stable Command Registry IDs. |
| File, registry, process, shell, DLL, and network operations | Unsupported | Rejected explicitly; no capability is exposed. |
| Every command not listed above | Unsupported | Rejected explicitly. |

All document changes produced by one translated macro are committed through the existing frozen `maru` API inside one Undo group. The translator receives only `currentDocument` permission. It cannot read arbitrary files, execute a process, access the clipboard, or expand the native JavaScript API. Native `.js` macro loading and execution are byte-for-byte unchanged whether the compatibility flag is on or off.

The executable clean-room corpus in `MaruCompatibilityCorpus.swift` is
dedicated to CC0-1.0 and contains no copied vendor material. Tests execute its
language, editing, search, window/outline, and diagnostic cases and generate
`generated-macro-compatibility-report.md`; any FAIL blocks completion.
