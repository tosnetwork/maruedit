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
| `app.macroMenu` | Macro Menu | Toolbar/Function Keys | — | Opens the registered macro menu from configurable chrome |
| `file.new` | New File | File | ⌘N | `AppCoordinator.newDocument()` |
| `file.newFromTemplate` | New from Template… | File | — | `AppCoordinator.newDocumentFromTemplate()` |
| `file.open` | Open... | File | ⌘O | `AppCoordinator.openDocument()` |
| `file.openFolder` | Open Folder... | File | ⌘⇧O | `AppCoordinator.openFolderPanel()` |
| `file.openPartial` | Open Partial File… | File | — | `AppCoordinator.openPartialFile()` |
| `file.openBinary` | Open in Binary Mode… | File | — | Opens editable comma-separated hexadecimal bytes, 16 per line |
| `file.projectHistory` | Project History… | File | — | Reopens a recently used project folder in the sidebar |
| `file.saveWorkspace` | Save Workspace As… | File | — | Exports open files, project root, active tab, cursor/fold/scroll and window state to `.marudesk` |
| `file.openWorkspace` | Open Workspace… | File | — | Restores a `.marudesk` desktop/workspace without discarding currently open unsaved tabs |
| `file.workspaceHistory` | Workspace History… | File | — | Restores a recently used `.marudesk` workspace |
| `file.closeAndOpen` | Close and Open… | File | — | `AppCoordinator.closeAndOpen()` |
| `window.tabList` | Tab List… | Window | — | Selects an open document from a complete list |
| `window.closeOtherTabs` | Close Other Tabs | Window | — | Closes all tabs except the active tab with save confirmation |
| `window.closeTabsLeft` | Close Tabs to the Left | Window | — | Closes tabs left of the active tab with save confirmation |
| `window.closeTabsRight` | Close Tabs to the Right | Window | — | Closes tabs right of the active tab with save confirmation |
| `window.focusEditor` | Focus Editor | Window | — | Moves keyboard focus to the editor |
| `window.focusUtilityPane` | Focus Utility Pane | Window | — | Reveals and focuses the utility pane |
| `file.save` | Save | File | ⌘S | `AppCoordinator.saveDocument()` |
| `file.saveAs` | Save As... | File | ⌘⇧S | `AppCoordinator.saveDocumentAs()` |
| `file.saveAndClose` | Save and Close | File | — | Saves the active tab when modified, then closes it only after a successful save |
| `file.saveAllAndClose` | Save All and Close | File | — | Saves and closes every tab in order, stopping immediately on cancellation or save failure |
| `file.closeTab` | Close Tab | File | ⌘W | `AppCoordinator.closeCurrentTab()` |
| `window.nextTab` | Next Tab | Window | ⌃Tab | `AppCoordinator.selectNextTab()` |
| `window.previousTab` | Previous Tab | Window | ⌃⇧Tab | `AppCoordinator.selectPreviousTab()` |
| `insert.dateTime` | Date and Time | Insert | — | `AppCoordinator.insertDateTime()` |
| `insert.pageBreak` | Page Break | Insert | — | `AppCoordinator.insertPageBreak()` |
| `insert.controlCode` | Control Code… | Insert | — | `AppCoordinator.insertControlCode()` |
| `app.help` | MaruEdit Help | Help | — | `AppCoordinator.showHelp()` |
| `macro.startRecording` | Start Recording | Macro | — | Starts a fresh CommandRegistry recording |
| `macro.stopRecording` | Stop Recording | Macro | — | Stops recording while retaining captured commands |
| `macro.playRecording` | Play Recorded Commands | Macro | — | Replays captured stable command IDs |
| `macro.saveRecording` | Save Recording as Macro… | Macro | — | Writes a non-overwriting reloadable JavaScript macro |
| `help.macros` | Macro Help | Help | — | `AppCoordinator.showMacroHelp()` |
| `help.shortcuts` | Keyboard Shortcut Reference | Help | — | `AppCoordinator.showShortcutReference()` |
| `help.checkUpdates` | Check for Updates… | Help | — | Opens the latest GitHub release |
| `help.support` | Support and Report an Issue… | Help | — | Opens the GitHub issue tracker |
| `other.fileTypeProfiles` | File-Type Profiles… | Other | — | Opens Settings directly at Files |
| `other.keyAssignments` | Key Assignments… | Other | — | Opens Settings directly at Key Bindings |
| `other.commandList` | Command List… | Other | — | Opens the complete registered-command list/customizer |
| `convert.halfWidth` | Convert to Half-Width | Convert | — | `LineEditCommand.halfWidth` |
| `convert.fullWidth` | Convert to Full-Width | Convert | — | `LineEditCommand.fullWidth` |
| `convert.hiragana` | Convert to Hiragana | Convert | — | `LineEditCommand.hiragana` |
| `convert.katakana` | Convert to Katakana | Convert | — | `LineEditCommand.katakana` |
| `convert.tabsToSpaces` | Convert Tabs to Spaces | Convert | — | `LineEditCommand.tabsToSpaces` |
| `convert.spacesToTabs` | Convert Leading Spaces to Tabs | Convert | — | `LineEditCommand.spacesToTabs` |
| `convert.halfWidthAlphanumeric` | Alphanumerics/Symbols/Spaces to Half-Width | Convert | — | Selective width conversion that preserves kana |
| `convert.fullWidthAlphanumeric` | Alphanumerics/Symbols/Spaces to Full-Width | Convert | — | Selective width conversion that preserves kana |
| `convert.halfWidthKatakana` | Katakana Only to Half-Width | Convert | — | Selective kana conversion that preserves Latin text |
| `convert.fullWidthKatakana` | Katakana Only to Full-Width | Convert | — | Selective kana conversion that preserves Latin text |
| `file.clearRecoveryData` | Clear Recovery Data... | File | — | `AppCoordinator.clearRecoveryData()` |
| `file.pageSetup` | Page Setup… | File | — | `AppCoordinator.showPageSetup()` |
| `file.print` | Print… | File | — | `AppCoordinator.printDocument()` |
| `file.reload` | Reload from Disk | File | — | `AppCoordinator.reloadDocument()` |
| `file.toggleViewMode` | View Mode | File | — | `AppCoordinator.toggleViewMode()` |
| `file.properties` | File Properties… | File | — | `AppCoordinator.showFileProperties()` |
| `file.appendRead` | Append Read… | File | — | `AppCoordinator.appendRead()` |
| `file.appendSave` | Append Save… | File | — | `AppCoordinator.appendSave()` |
| `insert.fileContents` | File Contents… | Insert | — | `AppCoordinator.insertFileContents()` |
| `file.rename` | Rename File… | File | — | `AppCoordinator.renameFile()` |
| `search.find` | Find... | Find | ⌘F | `AppCoordinator.showFind()` |
| `search.replace` | Find and Replace... | Find | ⌥⌘F | `AppCoordinator.showReplace()` |
| `search.replaceAll` | Replace All | Find | — | `AppCoordinator.replaceAll()` |
| `search.findNext` | Find Next | Find | ⌘G | `AppCoordinator.findNext()` |
| `search.findPrevious` | Find Previous | Find | ⇧⌘G | `AppCoordinator.findPrevious()` |
| `search.goToLine` | Go to Line... | Find | ⌘L | `AppCoordinator.showGoToLine()` |
| `search.quickOpen` | Quick Open... | Find | ⌘P | `AppCoordinator.showQuickOpen()` |
| `search.grep` | Find in Folder... | Find | ⇧⌘F | `AppCoordinator.showGrep()` |
| `search.grepCurrentDocument` | Grep Current Document | Find | — | `AppCoordinator.grepCurrentDocument()` |
| `search.grepOpenDocuments` | Grep All Open Documents | Find | — | `AppCoordinator.grepOpenDocuments()` |
| `search.refineGrepResults` | Refine Grep Results | Find | — | `AppCoordinator.refineGrepResults()` |
| `search.outputGrepDocument` | Output Grep Results as Document | Find | — | `AppCoordinator.outputGrepResultsAsDocument()` |
| `search.clearHistory` | Clear Search History | Find | — | `AppCoordinator.clearSearchHistory()` |
| `search.toggleCaseSensitive` | Case Sensitive | Search › Search Options | ⌥⌘C | Toggles the shared Find/Replace query flag |
| `search.toggleWholeWord` | Whole Word | Search › Search Options | ⌥⌘W | Toggles the shared Find/Replace query flag |
| `search.toggleRegex` | Regular Expression | Search › Search Options | ⌥⌘R | Toggles the shared Find/Replace query mode |
| `search.toggleFuzzy` | Fuzzy Width Search | Search › Search Options | ⌥⌘Z | Compatibility-normalizes full/half-width forms while preserving original match and capture ranges |
| `search.previousEditMark` | Previous Edit Mark | Search › Edit Marks | — | Navigates to the preceding changed-line gutter mark with wrapping |
| `search.nextEditMark` | Next Edit Mark | Search › Edit Marks | — | Navigates to the following changed-line gutter mark with wrapping |
| `search.clearEditMarks` | Clear Edit Marks | Search › Edit Marks | — | Clears changed-line marks without changing the document dirty state |
| `search.toggleHighlight` | Highlight Search String | Search › All Matches | — | Toggles temporary highlighting for every active-query match |
| `search.selectAllMatches` | Select All Matches | Search › All Matches | — | Creates one selection per match through the unified search engine |
| `search.colorAllMatches` | Color All Matches | Search › All Matches | — | Applies a rotating temporary match color |
| `search.clearMatchColors` | Clear Match Colors | Search › All Matches | — | Removes temporary match coloring and gutter markers |
| `search.listAllMatches` | List All Matches | Search › All Matches | — | Lists matching lines in the Results utility pane |
| `search.returnToStart` | Return to Search Start | Search | — | Restores the caret captured when search began |
| `search.setRange` | Set Selection as Search Range | Search › Search Range | — | Persists the current selection as the explicit search scope |
| `search.selectRange` | Select Search Range | Search › Search Range | — | Reselects the active explicit search scope |
| `search.clearRange` | Clear Search Range | Search › Search Range | — | Restores document-wide searching |
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
| `view.toggleRuler` | Show Character Ruler | View › Ruler | — | Shows or hides the classic horizontal character ruler |
| `view.rulerInterval8` | Ruler: 8-Column Units | View › Ruler | — | Uses source-oriented eight-column major ruler marks |
| `view.rulerInterval10` | Ruler: 10-Column Units | View › Ruler | — | Uses document-oriented ten-column major ruler marks |
| `view.toggleTabStops` | Show Tab Stops on Ruler | View › Ruler | — | Displays tab-stop markers using the active profile tab width |
| `view.splitVertical` | Split Editor Vertically | View | — | `AppCoordinator.splitEditorVertical()` |
| `view.splitHorizontal` | Split Editor Horizontally | View | — | `AppCoordinator.splitEditorHorizontal()` |
| `view.closeSplit` | Close Editor Split | View | — | `AppCoordinator.closeEditorSplit()` |
| `view.toggleLinkedScrolling` | Linked Editor Scrolling | View | — | `AppCoordinator.toggleLinkedEditorScrolling()` |
| `view.toggleTableMode` | CSV/TSV Table Mode | View | — | `AppCoordinator.toggleTableMode()` |
| `view.toggleVerticalLayout` | Vertical Writing Mode | View | — | Switches between AppKit horizontal and native vertical glyph layout |
| `view.toggleColumnLayout` | Column Layout Mode | View | — | Flows one TextKit storage continuously through ordered editable columns |
| `view.toggleLineNumbers` | Show Line Numbers | View | — | Shows or hides the editor gutter |
| `view.toggleHeading` | Show Heading Bar | View | — | Shows or hides the classic outline/current-document heading |
| `view.toggleFunctionKeys` | Show Function-Key Bar | View | — | Shows or hides the twelve-slot classic function-key strip |
| `view.toggleStatusBar` | Show Status Bar | View | — | Shows or hides the interactive status fields |
| `view.toggleOutputPane` | Show Output Pane | View | — | Shows or hides grep, macro and external-command output |
| `view.focusOutputPane` | Focus Output Pane | View | — | Shows the output pane if necessary and moves keyboard focus to it |
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
| `edit.toggleInputMode` | Toggle Insert/Overwrite Mode | Edit | — | `AppCoordinator.toggleInputMode()` |
| `edit.moveWordLeft` | Move Word Left | Edit | — | `AppCoordinator.moveWordLeft()` |
| `edit.moveWordRight` | Move Word Right | Edit | — | `AppCoordinator.moveWordRight()` |
| `edit.moveParagraphStart` | Move to Paragraph Start | Edit | — | `AppCoordinator.moveToParagraphStart()` |
| `edit.moveParagraphEnd` | Move to Paragraph End | Edit | — | `AppCoordinator.moveToParagraphEnd()` |
| `edit.deleteWordBackward` | Delete Word Backward | Edit | — | `AppCoordinator.deleteWordBackward()` |
| `edit.deleteWordForward` | Delete Word Forward | Edit | — | `AppCoordinator.deleteWordForward()` |
| `edit.titlecase` | Convert to Title Case | Edit | — | `performLineCommand(.titlecase)` |
| `edit.completeWord` | Complete Word | Edit | — | `AppCoordinator.showCompletions()` |
| `edit.selectWord` | Select Word | Edit | — | Selects the word at the primary caret |
| `edit.selectLine` | Select Line | Edit | — | Selects the complete logical line |
| `edit.selectParagraph` | Select Paragraph | Edit | — | Selects the paragraph at the primary caret |
| `edit.copyQuoted` | Copy with Quote Prefix | Edit | — | Copies selected lines with `> ` prefixes |
| `edit.pasteQuoted` | Paste Removing Quote Prefix | Edit | — | Removes `>` quote prefixes while pasting |
| `edit.clipboardHistory` | Clipboard History… | Edit | — | Selects, pastes or clears recently observed text clipboard values |
| `edit.restoreDeletion` | Restore Last Deleted Text | Edit | — | Reinserts the most recently deleted text at every active selection |
| `edit.correctCapsLock` | Correct Caps Lock Mistake | Edit | — | Toggles the selected/current word's letter case; macOS owns the physical Caps Lock state |
| `edit.reconvert` | Reconvert with Input Method | Edit | — | Routes the selection to the active macOS input method's native reconversion command |
| `navigate.toggleBookmark` | Toggle Bookmark | Edit | — | `AppCoordinator.toggleBookmark()` |
| `navigate.nextBookmark` | Next Bookmark | Edit | — | `AppCoordinator.nextBookmark()` |
| `navigate.previousBookmark` | Previous Bookmark | Edit | — | `AppCoordinator.previousBookmark()` |
| `navigate.bookmarkList` | Bookmark List… | Bookmark | — | `AppCoordinator.showBookmarkList()` |
| `navigate.clearBookmarks` | Clear Bookmarks | Edit | — | `AppCoordinator.clearBookmarks()` |
| `navigate.toggleFold` | Toggle Fold | Edit | — | `AppCoordinator.toggleFold()` |
| `navigate.collapseAllFolds` | Collapse All Folds | Edit | — | `AppCoordinator.collapseAllFolds()` |
| `navigate.expandAllFolds` | Expand All Folds | Edit | — | `AppCoordinator.expandAllFolds()` |
| `navigate.beginPartialOutline` | Edit Current Outline Region | Edit | — | `AppCoordinator.beginPartialOutlineEditing()` |
| `navigate.endPartialOutline` | Show Full Document | Edit | — | `AppCoordinator.endPartialOutlineEditing()` |
| `navigate.markerRed` | Toggle Red Marker | Edit | — | `AppCoordinator.toggleMarker(.red)` |
| `navigate.markerYellow` | Toggle Yellow Marker | Edit | — | `AppCoordinator.toggleMarker(.yellow)` |
| `navigate.markerBlue` | Toggle Blue Marker | Edit | — | `AppCoordinator.toggleMarker(.blue)` |
| `navigate.nextMarker` | Next Marker | Edit | — | `AppCoordinator.nextMarker()` |
| `navigate.previousMarker` | Previous Marker | Edit | — | `AppCoordinator.previousMarker()` |
| `navigate.highlightList` | Highlight List… | Highlight | — | Lists, previews, navigates and removes color markers |
| `navigate.clearMarkers` | Clear Markers | Edit | — | `AppCoordinator.clearMarkers()` |
| `navigate.compareNextDocument` | Compare with Next Document | Navigate | — | `AppCoordinator.compareWithNextDocument()` |
| `navigate.nextDifference` | Next Difference | Navigate | — | `AppCoordinator.nextDifference()` |
| `navigate.previousDifference` | Previous Difference | Navigate | — | `AppCoordinator.previousDifference()` |
| `navigate.mergeDifferenceFromRight` | Accept Difference from Right | Navigate | — | `AppCoordinator.mergeCurrentDifferenceFromRight()` |
| `navigate.tagJump` | Jump to Tag… | Navigate | — | `AppCoordinator.showTagJump()` |
| `navigate.directTagJump` | Direct Tag Jump | Navigate | — | `AppCoordinator.directTagJump()` |
| `navigate.backTagJump` | Back from Tag | Navigate | — | `AppCoordinator.backTagJump()` |

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
