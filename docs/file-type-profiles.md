# FileType Profiles

MaruEdit file-type profiles use JSON schema version 5. A profile matches exact
filenames and/or filename extensions, then supplies the editor behavior for a
newly opened document.

```json
{
  "schemaVersion": 5,
  "id": "user.example-script",
  "name": "Example Script",
  "filenamePatterns": ["Examplefile"],
  "extensions": ["example"],
  "priority": 10,
  "settings": {
    "tabWidth": 4,
    "indentWidth": 2,
    "indentStyle": "spaces",
    "wrapLines": true,
    "wrapMode": "fixed",
    "wrapColumn": 160,
    "encoding": "UTF-8",
    "syntax": "shell",
    "lineComment": "#",
    "blockCommentStart": null,
    "blockCommentEnd": null,
    "appearance": {
      "fontName": "Menlo", "fontSize": 14,
      "foregroundHex": "#202020", "backgroundHex": "#FAFAF5",
      "selectionHex": "#B8D8FF"
    },
    "foldingEnabled": true,
    "templatePath": "/Users/me/Templates/example.txt",
    "loadPolicy": {
      "opensReadOnly": false,
      "encodingCandidateOrder": ["UTF-8", "Windows-31J"]
    },
    "savePolicy": {
      "backup": {"enabled": true, "destination": "sibling", "directoryPath": null, "suffix": ".bak", "maximumCopies": 5},
      "ensuresFinalNewline": true,
      "trimsTrailingWhitespace": false
    }
  }
}
```

Extensions may be written with or without a leading dot and matching is
case-insensitive. Resolution uses this deterministic order:

1. exact filename, then extension, then Plain Text fallback;
2. user profile before built-in profile;
3. larger numeric priority;
4. lexicographically smaller stable profile ID.

The application ships immutable profiles for Plain Text, Swift, C/C++, Go,
Rust, JavaScript, JSON, Markdown, and Shell. User profiles live separately in
`Application Support/MaruEdit/FileTypeProfiles`, so application updates cannot
replace them. A user profile may deliberately reuse a built-in ID and will win
resolution while leaving the packaged definition unchanged.

`FileTypeProfileStore` imports and exports the same JSON representation. Import
rejects unsupported schema versions and writes atomically into the user-profile
directory. Profiles are resolved before file decoding, allowing an explicit
encoding to control loading; syntax, tab and indent widths, indent style,
wrapping, and comment delimiters then apply to the document and editor.

Schema 4 additionally controls font and colors, spelling, completion sources and
ranking, outline rules, folding, UTF-8 templates, bounded timestamped backups,
read-only loading, ordered decoding candidates, and explicit save transforms.
Template and dictionary reads have size limits. Backup paths and failures are
reported; MaruEdit never silently skips a configured backup before overwriting.
Older profiles decode with the new fields disabled, then migrate on import.
