# MaruEdit Macro API v1

The frozen global `maru` object reports `apiVersion === 1`. Macros should check
this value before relying on newer capabilities. The engine exposes values and
functions only; no AppKit, document, controller, or Objective-C object crosses
the JavaScript boundary.

## Commands

`maru.commands.run(commandID)` executes a stable Command Registry ID and
returns a Promise resolving to `true` when the command ran or `false` when it
was unknown or disabled. Return the Promise from the script when its resolved
value should become the macro result.

## Document and editor

- `maru.document.getText()` returns the active document text.
- `maru.document.setText(string)` replaces the complete document.
- `maru.editor.getSelections()` returns `{ location, length }` objects.
- `maru.editor.setSelections(ranges)` validates and applies non-empty ranges,
  returning `false` if any range is outside the document.
- `maru.editor.replaceSelections(string)` replaces every normalized selection
  with the same string and leaves a cursor after each replacement.

Selection coordinates are zero-based UTF-16 offsets and lengths, matching
TextKit and `NSRange`; they are not grapheme indices or display columns.

## Clipboard and UI

- `maru.clipboard.readText()` returns plain text or an empty string.
- `maru.clipboard.writeText(string)` replaces plain-text clipboard contents.
- `maru.ui.message(value)` shows a transient application message.
- `maru.ui.prompt(message, initialValue = '')` returns entered text or `null`
  after cancellation.

## Undo grouping

`maru.undo.group(name, callback)` brackets every edit made by the callback in
one native Undo group. The group is closed with `finally`, including when the
callback throws.

```javascript
const ranges = maru.editor.getSelections();
const text = maru.document.getText();
maru.undo.group('Uppercase selection', () => {
  // Derive selected text using UTF-16-aware application logic when non-ASCII
  // offsets matter; this short ASCII example is intentionally simple.
  const selected = text.substring(ranges[0].location,
    ranges[0].location + ranges[0].length);
  maru.editor.replaceSelections(maru.text.uppercase(selected));
});
```

Argument type failures throw `TypeError`. JavaScript failures are returned as
`MacroJavaScriptError` with message, stack, line, and column when available.
Cancellation and timeout behavior is defined in `macro-engine.md`.
