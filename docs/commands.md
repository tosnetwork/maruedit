# Command Registry

MaruEdit routes every stable, app-level menu action through a
`CommandRegistry` (ROADMAP.md M1-03 / ADR-006) instead of wiring menu items
directly to `@objc` methods. Menus, and eventually key bindings, macros,
and a command palette, all refer to commands only by their `CommandID` —
never by selector — so those surfaces can be reconfigured independently of
how a command is implemented.

This file is currently maintained by hand from
`Sources/MaruEditApp/Commands/AppCommands.swift`. If the command list grows
significantly, replace this with a small script that generates it from
`CommandRegistry.allDefinitions` instead of keeping this in sync manually.

## Registered Commands

| Command ID | Title | Menu | Default Shortcut | Implementation |
|---|---|---|---|---|
| `file.new` | New File | File | ⌘N | `AppCoordinator.newDocument()` |
| `file.open` | Open... | File | ⌘O | `AppCoordinator.openDocument()` |
| `file.openFolder` | Open Folder... | File | ⌘⇧O | `AppCoordinator.openFolderPanel()` |
| `file.save` | Save | File | ⌘S | `AppCoordinator.saveDocument()` |
| `file.saveAs` | Save As... | File | ⌘⇧S | `AppCoordinator.saveDocumentAs()` |
| `file.closeTab` | Close Tab | File | ⌘W | `AppCoordinator.closeCurrentTab()` |
| `file.clearRecoveryData` | Clear Recovery Data... | File | — | `AppCoordinator.clearRecoveryData()` |
| `search.find` | Find... | Find | ⌘F | `AppCoordinator.showFind()` |
| `search.replace` | Find and Replace... | Find | ⌥⌘F | `AppCoordinator.showReplace()` |
| `search.replaceAll` | Replace All | Find | — | `AppCoordinator.replaceAll()` |
| `search.findNext` | Find Next | Find | ⌘G | `AppCoordinator.findNext()` |
| `search.findPrevious` | Find Previous | Find | ⇧⌘G | `AppCoordinator.findPrevious()` |
| `search.goToLine` | Go to Line... | Find | ⌘L | `AppCoordinator.showGoToLine()` |
| `search.quickOpen` | Quick Open... | Find | ⌘P | `AppCoordinator.showQuickOpen()` |
| `search.grep` | Find in Folder... | Find | ⇧⌘F | `AppCoordinator.showGrep()` |
| `view.toggleSidebar` | Toggle Sidebar | View | ⌘B | `AppCoordinator.toggleSidebar()` |

All of them are enabled unconditionally right now (`isEnabled` always
returns `true`) — the app has no state yet where one of them shouldn't be
available. `CommandRegistryTests.testAppCommandsAreEnabledByDefault`
guards this.

M3-02 moved Go to Line off ⌘G, which macOS reserves for Find Next, onto
⌘L. Its Command ID is unchanged, so nothing that refers to the command
(menus, and later key bindings and macros) had to change.

## Not Yet Routed Through the Registry

- **Standard editing** (Undo, Redo, Cut, Copy, Paste, Select All) and
  **Window** (Minimize, Zoom) menu items use built-in AppKit responder-chain
  selectors (`cut:`, `copy:`, `miniaturize:`, ...) with no target set, so
  the first responder handles them directly. These aren't MaruEdit-specific
  commands, so they're intentionally left outside the registry.
- **Open Recent**, **Clear Recent**, and (new in M2-02) **Reopen with
  Encoding** are dynamically generated — per recent file/folder, or per
  candidate `TextEncoding` — rebuilt every time the submenu opens, so they
  don't map cleanly onto a single stable `CommandID`. They still go
  through `AppCoordinator`/`MainWindowController`, just not through
  `CommandRegistry.execute`.
- The Find Bar's **option toggles** (⌥⌘C case sensitive, ⌥⌘W whole word,
  ⌥⌘R regular expression, added in M3-02) are handled by
  `FindBarView.performKeyEquivalent(with:)` and are local to that bar
  rather than app-level commands: they change the state of one transient
  input surface, and they only exist while it is visible.
- The global **Cmd+P** key-monitor in `MainWindowController` (independent
  of the Find menu's Quick Open item) still calls `showQuickOpen()`
  directly rather than `CommandRegistry.execute(.searchQuickOpen, ...)`,
  because `MainWindowController` has no reference back to `AppCoordinator`
  or the registry. ROADMAP.md M1-03 explicitly allows shortcut *parsing* to
  stay ad hoc for now ("may remain temporarily"); wiring this one
  remaining case through the registry is deferred to M1-05
  (`KeyBindingManager`), which will replace this ad-hoc `NSEvent` monitor
  outright.

Counting only MaruEdit's own static, non-dynamic menu actions (the ones
listed above, excluding the standard-AppKit and dynamic-recent-items
cases), all of them — 100% — execute through the registry, exceeding
M1-03's ≥90% acceptance target.
