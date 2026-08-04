# Key Bindings

MaruEdit key-binding profiles use schema version 1. Commands are referenced by
stable `CommandID`, never by localized menu title or Objective-C selector.

```json
{
  "schemaVersion": 1,
  "name": "My Profile",
  "bindings": [
    { "keys": ["cmd+f"], "command": "search.find" },
    { "keys": ["ctrl+k", "ctrl+c"], "command": "edit.toggleComment" }
  ]
}
```

Keys use portable characters or semantic names such as `up`, `down`, `tab`,
`escape`, and `f1`; modifiers are `cmd`, `ctrl`, `opt`, and `shift`. Hardware
key codes are deliberately not part of the file format. A sequence may contain
two gestures so the same schema can represent M5-02 chords.

The built-in profiles are:

- **macOS Standard**, with conventional Mac shortcuts and MaruEdit's existing
  multiple-selection shortcuts.
- **Maru Classic**, an independent control-key-oriented profile with function
  keys for Find Next/Previous and bookmark navigation.

`KeyBindingManager` validates the schema, reports duplicate sequences, imports
and exports JSON atomically, and restores either built-in profile. Activating a
profile updates every Command Registry menu item's displayed shortcut.

## Two-step chords

`ChordStateMachine` waits 1.5 seconds for the second gesture. While pending,
the status bar shows the normalized prefix. Escape cancels, an unknown second
gesture reports an invalid chord, and timeout clears the state. A completed
sequence executes its stable command through `CommandRegistry`.

The key router does not inspect chord input while AppKit reports marked text or
MaruEdit owns an IME composition snapshot. An unmodified character after a
pending prefix cancels the chord but is still delivered to TextKit, covering
the first event that begins an IME before AppKit exposes marked text. Thus
ordinary Latin or CJK input is never consumed as an invalid chord suffix.
Profiles report both duplicate full sequences and ambiguous cases where a
single-step command is also a two-step prefix. Maru Classic includes
`ctrl+k`, `ctrl+c` for Toggle Comment as the built-in chord example.
