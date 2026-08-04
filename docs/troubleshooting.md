# Troubleshooting

## Text looks garbled

Do not save over the source. Reopen with an explicit encoding, compare the
preview, and confirm the status-bar encoding. Keep a copy when testing a legacy
Japanese encoding.

## Newlines changed

Check the line-ending indicator before Save. Mixed files require an explicit
normalization choice; use LF, CRLF, or CR appropriate to the consuming tool.

## Save reports an external change

Another process changed, replaced, moved, or deleted the file. Reload only if
the disk version should win. Otherwise save the in-memory text to another path
or explicitly overwrite after reviewing the conflict.

## Grep misses a file

Review root access, ignore/hidden-file options, binary detection, and encoding.
Package and symlink traversal is deliberately constrained. A cancelled scan is
labelled cancelled and contains only results delivered before cancellation.

## A key binding does not run

Check profile conflicts, chord timeout, and whether an IME composition is
active. Escape cancels a pending chord. Export the profile and verify that it
uses a stable ID from [commands.md](commands.md).

## A macro or external command is denied

Grant only the capability it needs in Settings. File access may require a new
bookmark after a file moves. External-command paths must be absolute; shell
syntax requires shell mode and confirmation. See [External Commands](external-commands.md).

## Recovery appears after a crash

Recovery is a separate snapshot and never overwrites the source automatically.
Open it, compare it with the source, and save intentionally. Corrupt recovery
or session data is quarantined so startup can continue.

## A downloaded app is blocked

Verify the release checksum and signature. Do not remove quarantine from an
unknown artifact. A source build is the safe fallback until a signed,
notarized release is available.

For reproducible diagnostics run `swift test`, `bash build.sh`, and
`bash scripts/beta-smoke.sh`, then include macOS version, architecture, commit,
and the smallest reproducing file in an issue.
