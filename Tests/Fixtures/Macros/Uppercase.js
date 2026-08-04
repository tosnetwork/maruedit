// @maru-name: Uppercase Selection
// @maru-description: Uppercases every active selection.
// @maru-shortcut: cmd+shift+9
// @maru-permissions: currentDocument

maru.undo.group('Uppercase Selection', () => {
  maru.editor.replaceSelections('UPPER');
});
