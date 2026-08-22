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

The download requires macOS 13 or later.

## Verifying and opening this build

This build is signed ad-hoc and is not notarized by Apple, so macOS cannot tell
you who built it. Two consequences follow, and they are separate:

**1. Check what you downloaded.** The published SHA-256 is what stands in for a
developer signature:

```bash
shasum -a 256 -c MaruEdit-0.1.6.dmg.sha256
```

Be clear about its limit: the DMG and the checksum come from the same GitHub
release, so this catches a corrupted or truncated download, not a compromised
release. If you need a stronger guarantee, rebuild from the tag —
`docs/reproducible-releases.md` gives the procedure, including why a rebuilt
binary's digest normally differs from the published one and what inputs have to
match before a comparison means anything.

**2. Let it open.** macOS quarantines anything downloaded from the internet and
will refuse to launch a build it cannot attest. After copying MaruEdit to
Applications, remove the quarantine attribute:

```bash
xattr -dr com.apple.quarantine /Applications/MaruEdit.app
```

The `-r` is required in this release. The bundle now contains a second
executable — the MCP bridge — and a non-recursive removal leaves it
quarantined, so the agent interface would fail to start while the editor
appeared to work.

Alternatively, launch it once, let macOS block it, then allow it under **System
Settings → Privacy & Security → Open Anyway**. Recent macOS versions no longer
offer the older Control-click → Open override for apps that fail notarization,
so that route may not appear.

`spctl --assess` reports `rejected` for this build either way, including after
the quarantine attribute is removed. That is the absence of notarization, not a
sign of a damaged download.

Run these commands only if you trust this repository. Removing quarantine
disables the only check macOS was performing, which is why the checksum step
comes first.

MaruEdit is an independent open-source project and is not affiliated with or
endorsed by any commercial editor vendor. See `NOTICE.md` and `UPSTREAM.md` for
license and provenance information.
