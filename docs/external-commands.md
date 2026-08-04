# External Commands

MaruEdit loads external commands from:

`~/Library/Application Support/MaruEdit/ExternalCommands.json`

Use **Tools > Open External Commands Configuration** to create and open the file, then **Reload External Commands** after editing it. Each entry becomes both a Tools menu item and a dynamic `CommandRegistry` command named `external.user.<id>`.

## Schema version 1

```json
[
  {
    "schemaVersion": 1,
    "id": "sort-selection",
    "name": "Sort Selection",
    "executable": "/usr/bin/sort",
    "arguments": [],
    "workingDirectory": "none",
    "inheritedEnvironment": ["LANG"],
    "environment": { "LC_ALL": "C" },
    "input": "selection",
    "output": "replaceSelection",
    "shellMode": false
  }
]
```

Executable paths and explicit working directories must be absolute. `arguments` are passed directly to `execve` as separate values: MaruEdit does not interpolate, quote, or evaluate them. Only variables named in `inheritedEnvironment` are copied from MaruEdit's environment; values in `environment` override inherited values.

`input` is `none`, `currentDocument`, or `selection`. Selection input uses the primary selection. `output` is `newDocument`, `replaceSelection`, `outputPane`, or `clipboard`; replacement applies the result to every active selection as one undoable edit. Document and clipboard outputs are applied only after a successful exit. Stdout and stderr stream independently into the Output Pane, whose Stop button cancels the process.

`workingDirectory` is `none`, `currentDocumentDirectory`, or `explicit`. For `explicit`, provide `workingDirectoryPath`.

## Unsaved documents

Current-document and selection input work for unnamed or modified documents because MaruEdit sends the in-memory text. All output modes also work. `currentDocumentDirectory` requires a saved document with a file URL and fails before launch otherwise; use `none` or `explicit` for an unnamed document.

## Shell mode

Direct mode rejects shell executables. If shell syntax is truly required, set `shellMode` to `true` and provide `shellCommand`. Shell entries carry a warning marker in the Tools menu and require confirmation every time because substitutions, redirects, and chained commands are interpreted by `/bin/zsh -c`.

External commands run with the user's authority and can modify files outside MaruEdit. Prefer direct mode, absolute executables, a minimal environment allowlist, and commands that accept document text through standard input.
