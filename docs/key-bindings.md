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
profile updates every Command Registry menu item's displayed shortcut. Chord
prefix conflicts and runtime chord dispatch are added in M5-02.
