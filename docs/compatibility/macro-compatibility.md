# Experimental Hidemaru Macro Compatibility

This feature is experimental, incomplete, and disabled by default. It is a clean-room implementation of the public behavior documented below; it does not contain or depend on Hidemaru source code, binaries, private APIs, or copied help text. MaruEdit does not claim general Hidemaru macro compatibility.

Enable it for one launch with `MARUEDIT_ENABLE_HIDEMARU_COMPATIBILITY=1`, or set the `ExperimentalHidemaruMacroCompatibility` user default to `true`, then reload macros. UTF-8 `.mac` files in the normal MaruEdit Macros directory appear with “(Experimental)” in their menu title and a separate `macro.compat.*` command ID. When disabled, `.mac` files are ignored.

The parser accepts case-insensitive command names, semicolon-separated statements, `//` comments, and quoted strings with `\\`, `\"`, `\n`, and `\t`. Unsupported commands fail the complete macro with a line-numbered diagnostic. They are never guessed, partially executed, or forwarded to another interpreter.

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
| Variables, labels, flow control, functions | Unsupported | Rejected explicitly. |
| File, registry, process, shell, DLL, and network operations | Unsupported | Rejected explicitly; no capability is exposed. |
| Every command not listed above | Unsupported | Rejected explicitly. |

All document changes produced by one translated macro are committed through the existing frozen `maru` API inside one Undo group. The translator receives only `currentDocument` permission. It cannot read arbitrary files, execute a process, access the clipboard, or expand the native JavaScript API. Native `.js` macro loading and execution are byte-for-byte unchanged whether the compatibility flag is on or off.
