# User Macros

MaruEdit scans `~/Library/Application Support/MaruEdit/Macros` recursively for
UTF-8 JavaScript files. Choose **Macro > Open Macro Folder** to create and open
that directory, then **Reload Macros** after editing files.

Metadata is read from `// @maru-…:` comments in the first 40 lines:

```javascript
// @maru-name: Uppercase Selection
// @maru-description: Uppercases every active selection.
// @maru-shortcut: cmd+shift+9
// @maru-permissions: currentDocument, clipboard
```

The name falls back to the filename. Permissions are typed values:
`currentDocument`, `clipboard`, `otherFiles`, `externalCommands`, and `network`.
M6-04 defines their authorization behavior; metadata does not itself grant a
capability.

## Permissions

Every macro receives current-document access by default. Clipboard APIs appear
only when `clipboard` is declared. `otherFiles` opens a native directory picker;
the selected directory is remembered with a security-scoped bookmark and its
scope is active only while that macro runs. `externalCommands` requires a
separate warning confirmation. Allow and Deny decisions are remembered by
stable macro Command ID.

Choose **Macro > Manage Permissions** to inspect the remembered macro,
capability, decision, and directory path, and revoke any entry. Revocation
causes the next request to ask again.

Network access is not grantable. A macro declaring `network` is rejected before
execution, and JavaScript contexts expose no `fetch`, `XMLHttpRequest`,
`WebSocket`, or `EventSource`. Permission rejection details are written to the
Macro Error Console.

Each file receives a stable `macro.user.…` Command ID derived from its relative
path. Enabled macros appear in the Macro menu and their portable shortcut is
installed as a dynamic KeyBinding routed through CommandRegistry. Dynamic
bindings do not alter or export the selected key-binding profile.

Use **Macro > Enable Macros** to toggle individual files. Disabled IDs persist
across relaunches. Removing a file and reloading removes its command and
shortcut. Load and execution failures, including JavaScript stacks, appear in
the timestamped **Macro Error Console**; the console keeps the newest 500
entries.
