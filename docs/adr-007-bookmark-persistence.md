# ADR-007: Bookmarks Are Session-Ephemeral in 1.0

- Status: Accepted
- Date: 2026-08-04

## Decision

Bookmarks belong to an open `Document`, move with edits, and survive tab switches while that document remains open. They are not written into `SessionState` and therefore do not survive application relaunch in the 1.0 schema.

## Rationale

Persisting line anchors safely needs a stale-file policy: a saved line number or UTF-16 offset can silently identify unrelated text after an external edit. MaruEdit does not yet store contextual anchors or a content revision in its session records. Treating bookmarks as ephemeral avoids presenting stale markers as trustworthy and keeps the existing session schema backward compatible.

Persistent bookmarks can be introduced in a later schema with contextual matching and an explicit stale-anchor state. Command IDs and the document-owned API do not need to change when that happens.
