# MaruEdit 0.1.6

MaruEdit 0.1.6 adds an automation interface that lets an external AI agent —
Claude Code, Codex, or anything else that speaks the Model Context Protocol —
read and edit documents open in MaruEdit, under grants a person approves and
can revoke.

## Highlights

- **Agent automation over MCP.** A bridge shipped inside the app bundle exposes
  MaruEdit's open documents to an MCP client: list and read documents, search
  them, move the cursor, apply edits, and save. Every write carries the
  revisions it was computed against, so an edit based on a stale read is
  refused and told the current state rather than overwriting work the person
  did in the meantime. One agent call becomes one undo entry.

- **The interface is off by default.** Turn it on in Settings; until then no
  socket is created and nothing is exposed. Each agent configuration pairs once
  through a verification code shown in MaruEdit, and every connection starts
  with a grant frozen to the documents already open — approving an agent does
  not approve documents opened later.

- **Nothing is granted by being registered.** File access is limited to folders
  explicitly authorized for that connection, with symbolic links out of them
  refused. Editor commands are exposed one at a time rather than in bulk, and a
  command names the window it acts on so switching tabs mid-call cannot
  redirect it.

- **Search accepts regular expressions.** Patterns that can backtrack
  exponentially are refused with an explanation of how to rewrite them, because
  a started match cannot be interrupted; what runs is bounded and capped.

- **Safer saving.** A document opened by an agent now records the identity of
  the file it actually read, so an in-place save over a file that was replaced
  underneath is refused rather than silently overwriting it. A file with no
  recorded baseline is reported as unknown rather than unchanged.

## What the automation interface is, and is not

Any program running as your user account can read MaruEdit's session token and
connect. The grants exist so that agent activity is deliberate, attributable,
visible, and revocable — not as a barrier against a hostile local program. This
build has no stable code signature, so agent credentials are kept in a file only
your account can read; MaruEdit says so during pairing rather than implying
more.

The download requires macOS 13 or later. Verify the DMG against the attached
SHA-256 file before installation.

## Unsigned preview

This build is not yet signed with a Developer ID Application certificate or
notarized by Apple. macOS may block its first launch. After copying MaruEdit to
Applications, Control-click it, choose **Open**, and confirm only if you trust
this repository. If it remains blocked, use **System Settings → Privacy &
Security → Open Anyway**. As a last resort, after verifying the attached
SHA-256 checksum, remove only MaruEdit's quarantine attribute:

```bash
xattr -dr com.apple.quarantine /Applications/MaruEdit.app
```

The `-r` matters in this release: the app bundle now contains a second
executable, the MCP bridge, and a non-recursive removal would leave it
quarantined.

MaruEdit is an independent open-source project and is not affiliated with or
endorsed by any commercial editor vendor. See `NOTICE.md` and `UPSTREAM.md` for
license and provenance information.
