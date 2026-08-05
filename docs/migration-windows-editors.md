# Migration from Windows-Style Editors

MaruEdit uses macOS conventions by default: Command replaces Control for most
menu shortcuts, Option moves by word, and Command-Click adds selections. Pick
the **Maru Classic** key-binding profile for a control-key and function-key
oriented starting point, then export JSON and customize stable command IDs.

Windows text files do not need conversion before opening. CRLF, BOM state,
Shift JIS, EUC-JP, and ISO-2022-JP are detected/preserved where supported. The
status bar makes encoding and newline choices visible before saving.

Common workflow mappings:

| Windows-style workflow | MaruEdit |
|---|---|
| Search current file | Find/Replace bar, literal or regex |
| Search a folder | Folder Grep result view |
| Replace across files | Grep Replace preview, then apply |
| Rectangular selection | BOX selection using visual columns |
| Repeat an edit | Multiple selections or a JavaScript macro |
| Launch a tool/filter | Controlled external-command profile |
| Per-extension settings | File-type profiles |

MaruEdit is independent and does not load Maru binary plugins, proprietary
macro files, or configuration databases. Recreate automation through the
documented [Macro API](macro-api-v1.md) and [external commands](external-commands.md).
