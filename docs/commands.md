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
| `app.settings` | Settings... | MaruEdit | ⌘, | `AppCoordinator.showSettings()` |
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
| `search.clearHistory` | Clear Search History | Find | — | `AppCoordinator.clearSearchHistory()` |
| `view.toggleSidebar` | Toggle Sidebar | View | ⌘B | `AppCoordinator.toggleSidebar()` |
| `view.toggleWrap` | Wrap Lines | View | — | `AppCoordinator.toggleWrapLines()` |
| `view.toggleSpaces` | Show Spaces | View > Show Invisibles | — | `AppCoordinator.toggleInvisible(\.spaces)` |
| `view.toggleTabs` | Show Tabs | View > Show Invisibles | — | `AppCoordinator.toggleInvisible(\.tabs)` |
| `view.toggleLineEndings` | Show Line Endings | View > Show Invisibles | — | `AppCoordinator.toggleInvisible(\.lineEndings)` |
| `view.toggleFullWidthSpaces` | Show Full-Width Spaces | View > Show Invisibles | — | `AppCoordinator.toggleInvisible(\.fullWidthSpaces)` |
| `view.tabWidth2` | 2 Spaces | View > Tab Width | — | `AppCoordinator.setTabWidth(2)` |
| `view.tabWidth4` | 4 Spaces | View > Tab Width | — | `AppCoordinator.setTabWidth(4)` |
| `view.tabWidth8` | 8 Spaces | View > Tab Width | — | `AppCoordinator.setTabWidth(8)` |
| `view.showFonts` | Show Fonts | View | — | `AppCoordinator.showFontPanel()` |
| `view.customizeMenus` | Customize Menus... | View | — | `AppCoordinator.showMenuCustomization()` |
| `edit.addCursorAbove` | Add Cursor Above | Edit | ⌥⌘↑ | `AppCoordinator.addCursorAbove()` |
| `edit.addCursorBelow` | Add Cursor Below | Edit | ⌥⌘↓ | `AppCoordinator.addCursorBelow()` |
| `edit.selectNextOccurrence` | Select Next Occurrence | Edit | ⌘D | `AppCoordinator.selectNextOccurrence()` |
| `edit.selectAllOccurrences` | Select All Occurrences | Edit | ⇧⌘L | `AppCoordinator.selectAllOccurrences()` |
| `edit.undoLastAddedCursor` | Undo Last Added Cursor | Edit | ⌘U | `AppCoordinator.undoLastAddedCursor()` |
| `edit.beginColumnSelection` | Begin Column Selection | Edit | — | `AppCoordinator.beginColumnSelection()` |
| `edit.deleteLine` | Delete Line | Edit > Lines | — | `performLineCommand(.delete)` |
| `edit.duplicateLine` | Duplicate Line/Selection | Edit > Lines | — | `performLineCommand(.duplicate)` |
| `edit.moveLineUp` | Move Line Up | Edit > Lines | — | `performLineCommand(.moveUp)` |
| `edit.moveLineDown` | Move Line Down | Edit > Lines | — | `performLineCommand(.moveDown)` |
| `edit.joinLines` | Join Lines | Edit > Lines | — | `performLineCommand(.join)` |
| `edit.trimTrailingWhitespace` | Trim Trailing Whitespace | Edit > Lines | — | `performLineCommand(.trimTrailingWhitespace)` |
| `edit.uppercase` | Convert to Uppercase | Edit > Lines | — | `performLineCommand(.uppercase)` |
| `edit.lowercase` | Convert to Lowercase | Edit > Lines | — | `performLineCommand(.lowercase)` |
| `edit.sortLines` | Sort Lines | Edit > Lines | — | `performLineCommand(.sort)` |
| `edit.reverseLines` | Reverse Lines | Edit > Lines | — | `performLineCommand(.reverse)` |
| `edit.indent` | Indent | Edit > Lines | — | `performLineCommand(.indent)` |
| `edit.outdent` | Outdent | Edit > Lines | — | `performLineCommand(.outdent)` |
| `edit.toggleComment` | Toggle Comment | Edit > Lines | — | `performLineCommand(.toggleComment)` |
| `navigate.toggleBookmark` | Toggle Bookmark | Edit | — | `AppCoordinator.toggleBookmark()` |
| `navigate.nextBookmark` | Next Bookmark | Edit | — | `AppCoordinator.nextBookmark()` |
| `navigate.previousBookmark` | Previous Bookmark | Edit | — | `AppCoordinator.previousBookmark()` |
| `navigate.clearBookmarks` | Clear Bookmarks | Edit | — | `AppCoordinator.clearBookmarks()` |
| `navigate.toggleFold` | Toggle Fold | Edit | — | `AppCoordinator.toggleFold()` |
| `navigate.collapseAllFolds` | Collapse All Folds | Edit | — | `AppCoordinator.collapseAllFolds()` |
| `navigate.expandAllFolds` | Expand All Folds | Edit | — | `AppCoordinator.expandAllFolds()` |

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
- Configurable shortcuts are resolved by `KeyBindingManager` and execute the
  resulting stable `CommandID` through this registry. Menu key equivalents are
  synchronized from the same active profile, so Quick Open and every other
  registered command no longer have a duplicate controller-level shortcut.

Counting only MaruEdit's own static, non-dynamic menu actions (the ones
listed above, excluding the standard-AppKit and dynamic-recent-items
cases), all of them — 100% — execute through the registry, exceeding
M1-03's ≥90% acceptance target.
