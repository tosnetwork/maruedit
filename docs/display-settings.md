# Display Settings

MaruEdit draws invisible-character markers as a TextKit overlay. The backing
`NSTextStorage.string` is never changed, so Find, save, Undo, IME composition,
and UTF-16 selections continue to see only the file's real characters.

| Character | Marker | Preference / Command |
|---|---|---|
| ASCII space (`U+0020`) | `·` | `view.toggleSpaces` |
| Tab (`U+0009`) | `→` | `view.toggleTabs` |
| Internal line ending (`U+000A`) | `¶` | `view.toggleLineEndings` |
| Full-width space (`U+3000`) | `□` | `view.toggleFullWidthSpaces` |

The four options are independent fields in Preferences schema v2. Decoding a
v1 preference blob supplies `false` for all four, preserving the previous
appearance. Marker drawing visits only the visible glyph range and is disabled
entirely above 100,000 UTF-16 units.

Preferences schema v6 adds OldMaru-style wrapping modes: no wrapping, window
width, fixed columns, and maximum width (8,000 columns). Fixed width defaults
to 160 columns and is calculated from the active editor font's half-width
character advance. The mode and column are editable in Settings > Editor.

Wrap and Tab Width commands create document display overrides. The resulting
precedence is document override, FileType Profile, then global Preferences.
They affect TextKit layout immediately and never edit content. The status bar's
visual-column calculation uses the effective tab width.

The default editor font is the platform-native monospaced system font (shown as
SF Mono in Settings). View > Show Fonts opens the standard macOS font panel.
`changeFont:` travels through the text view's responder-chain entry point, then
updates the editor-wide typed Preferences rather than adding rich-text font
runs to selected text.

MaruEdit observes `accessibilityDisplayOptionsDidChangeNotification`. When
Increase Contrast is active, the editor uses black/white foreground,
background, selection, caret, and marker colors. Colored syntax rules are
temporarily disabled so low-contrast token colors cannot override the system
preference. Switching the accessibility option or font never mutates logical
text.
