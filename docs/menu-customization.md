# Menu Customization

Choose **View > Customize Menus…** to show or hide MaruEdit commands. Changes
take effect immediately and survive relaunches. **Restore Defaults** makes all
customizable commands visible again.

The saved schema contains only stable command IDs, never displayed or localized
titles. This keeps a customization valid when the application language or a
command label changes. Schema v1 stores a sorted, duplicate-free list of hidden
IDs; unsupported future schemas fail safe by showing the default menu.

Required macOS items cannot be hidden. This includes application lifecycle and
system integration items (About, Settings, Services, Hide, Show All, and Quit),
standard Edit responder-chain actions, Window controls, and the Customize Menus
command itself. Required registered commands remain visible and their switches
are disabled in the customization window. Empty custom command groups and
adjacent separators are normalized after optional commands are hidden.
