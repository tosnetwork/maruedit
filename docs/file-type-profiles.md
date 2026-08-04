# FileType Profiles

MaruEdit file-type profiles use JSON schema version 1. A profile matches exact
filenames and/or filename extensions, then supplies the editor behavior for a
newly opened document.

```json
{
  "schemaVersion": 1,
  "id": "user.example-script",
  "name": "Example Script",
  "filenamePatterns": ["Examplefile"],
  "extensions": ["example"],
  "priority": 10,
  "settings": {
    "tabWidth": 4,
    "indentWidth": 2,
    "indentStyle": "spaces",
    "wrapLines": false,
    "encoding": "UTF-8",
    "syntax": "shell",
    "lineComment": "#",
    "blockCommentStart": null,
    "blockCommentEnd": null
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
