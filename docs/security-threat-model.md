# Macro and Process Threat Model

## Assets and trust boundaries

Protected assets are document contents, files reachable by the user, clipboard
text, preferences/bookmarks, recovery records, and process environment. File
contents, downloaded macros, external-command profiles, command output, paths,
and symlink targets are untrusted. The native application, capability bridge,
atomic file writer, and signed release pipeline are trusted components.

## JavaScript macros

Each run receives a fresh JavaScriptCore virtual machine and a frozen `maru`
value-only API. There is no `fetch`, WebSocket, filesystem API, AppKit object,
or arbitrary Objective-C bridge. Current-document and clipboard access require
declared permissions. File access uses explicit grants/security-scoped
bookmarks. Host boundaries check cancellation and timeout; undo grouping closes
even when script execution fails.

Residual risks include CPU work between cooperative checks, malicious edits
within granted capabilities, clipboard disclosure after consent, and defects in
JavaScriptCore. Users should inspect downloaded macros and grant the smallest
capability set. MaruEdit is not a safe environment for hostile code to which
the user grants document or file access.

## External processes

External commands are a deliberate escape from the macro sandbox. Direct mode
uses an absolute executable and argument vector without shell parsing, starts
from an explicit working-directory policy, and inherits only allowlisted
environment variables. Shell mode displays a warning and requires confirmation
on every run. Output replacement occurs only after successful exit; stdout and
stderr are bounded/streamed and execution can be cancelled.

Once approved, a process has the invoking user's OS authority and may read or
modify any resource that user can access. MaruEdit cannot make an arbitrary
executable safe. Avoid secrets in arguments/environment, prefer standard tools
by absolute path, and use document text over stdin.

## Files, recovery, and updates

Save and Grep Replace use atomic replacement and report partial failures.
External modification/inode replacement is detected before overwrite. Recovery
records are separate from source files and cannot overwrite them automatically.
MaruEdit contains no updater or telemetry client; release authenticity depends
on GitHub, the published SHA-256, Apple Developer ID signature, notarization,
and Gatekeeper verification.
