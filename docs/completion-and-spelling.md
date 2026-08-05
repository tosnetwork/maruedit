# Completion and spelling

Choose **Edit > Complete Word** to complete the word before the cursor. File Type
Profiles can set `settings.completion` with `includesCurrentDocument`, an array of
absolute UTF-8 `dictionaryPaths`, `ranking` (`frequency` or `alphabetical`),
`automatic`, and `presentation` (`list`, `tooltip`, or `status`). Dictionary files
are loaded away from the main thread, are limited to 2 MiB each and 16 files, and
completion scans at most 5,000,000 characters and returns at most 100 candidates.

`settings.spelling.enabled` enables the native macOS spelling underline and
correction menu for that profile. `automaticCorrection` additionally enables
system automatic corrections. Both default to off in profiles created before
schema version 3, so migration does not silently alter text-entry behavior.
