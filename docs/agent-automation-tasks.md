# Agent Automation — Task List

Working checklist for ADR-012 (`docs/adr-012-ai-agent-automation.md`), which
profiles ADR-011. One line per shippable unit. Phase 0 is expanded because it is
in progress; later phases stay at the granularity the ADR defines until they
start.

Branch: `ai-agent-automation-adr`.

---

## Phase 0 — Shared automation core

No socket, no bridge, no protocol. Everything here is internal refactoring that
both the existing macro engine and any future agent surface sit on.

### 0.1 Canonical text

- [x] `TextCanonicalization` — LF canonicalization and CR detection as pure
      value functions over the existing `LineEndingDetector`.
- [x] Canonicalize at `Document.init` and `Document.recovered`.
- [x] Canonicalize at `Document.fromTemplate`.
- [x] Canonicalize the Insert Template command's inserted text.
- [x] Canonicalize typing, paste, drop, and IME commits at
      `MaruTextView.committedString(from:)`, before text reaches storage.
- [x] Canonicalize every replacement handed to the transaction primitive, which
      covers macros, multi-cursor paste, box paste, and conversion pipelines.
- [x] Canonicalize Find/Replace and Replace All, which write text storage
      directly.
- [x] Canonicalize external-command output inserted into a document.
- [x] Canonicalize the generated grep-result document.
- [x] Backstop: `Document.content` canonicalizes on assignment, so a path nobody
      audited cannot introduce a CR.
- [x] Insert Control Code becomes value-backed and no longer offers CR
      (ADR-012 §3, second carve-out).

### 0.2 Revisions

- [x] Three counters on `Document`: `textRevision`, `metadataRevision`, and
      `selectionRevision` on each `EditorViewController`.
- [x] One mutation-notification boundary: `Document.content`'s observer bumps
      `textRevision`, so every existing assignment path is covered — the text
      view delegate, batch replacement, undo snapshot restore, reload, encoding
      change, and direct assignment.
- [x] Metadata observer covers encoding, BOM, line ending, file URL,
      permissions, read-only, view mode, overwrite protection, binary mode, and
      the resolved file-type profile.
- [x] No-op assignments bump nothing.
- [x] Selection boundary: `setSelections` and `textViewDidChangeSelection` both
      bump exactly once, the duplicate assignment after rehighlighting does not,
      and `synchronizeSharedDocumentState` routes its clamp through the same
      boundary instead of assigning `selectedRanges` directly.

### 0.3 Effective writability

- [x] `Document.profileForcesReadOnly` retains the profile load policy source
      that `refreshReadOnlyState()` used to drop.
- [x] `refreshReadOnlyState()` recomputes from all three sources — and so do
      both `reopen` paths, which had the same defect and were missed the first
      time through.
- [x] Split creation applies the same predicate instead of setting the secondary
      pane editable unconditionally.

### 0.4 Validated transaction primitive

- [x] `EditTransaction` value types: request, outcome, typed failure.
- [x] Strict validation before any mutation — non-empty, in bounds, no overlap.
- [x] Single text-storage editing block, applied in descending order.
- [x] One undo group with a caller-supplied action name.
- [x] Positional-state contract: bookmarks, color markers, temporary color
      markers, and the line index transform with the edit; selections are
      recomputed; the undo snapshot restores what it changed.
- [x] `batchReplace` becomes the lenient adapter over the strict primitive,
      preserving its documented drop-invalid and merge-overlap behavior.

### 0.5 Shared automation service

- [x] Process-lifetime opaque identifiers for documents, editors, and windows.
- [x] `EditorAutomationService`, `@MainActor`, value-only, owning document text,
      selections, replacement, transactions, and undo grouping.
- [x] `MacroCommandBridge` becomes an adapter over it; `maru.*` stays
      observably identical apart from the documented CR carve-out.
- [x] `Sendable` snapshot and result types for anything that will later cross to
      an off-main worker.
- [x] `MaruEditCore` builds under strict concurrency checking. `MaruEditApp` is
      main-actor AppKit code and stays on the default setting until it has
      something that actually leaves the main actor, in Phase 1.

### 0.6 Tests

- [x] Ingress: one case per row of ADR-012 §3's table.
- [x] Revisions: one case per row of §6.1's event table, including no-ops.
- [x] Selection revisions across programmatic, user, and cross-pane paths.
- [x] Read-only sources set and cleared independently, in both panes.
- [x] Transaction rejects an invalid batch without mutating anything.
- [x] Undo restores text, selections, bookmarks, and color markers together.
- [x] Insert Control Code maps SO, US, and DEL to the same bytes as before and
      no longer offers CR.
- [x] Existing macro tests pass unchanged apart from the CR carve-out.

**Exit:** met. 697 tests green, including 21 new ones covering the ingress
table, the revision event table, both selection paths, all three read-only
sources in both panes, transaction atomicity, and undo of positional state.

Deliberately deferred out of Phase 0, with reasons:

- The **split-pane undo ownership** decision (ADR-012 §5.3) belongs to Phase 2:
  the primitive labels its undo entry correctly, but a document shown in two
  panes still has two histories. Nothing in Phase 0 or 1 writes on an agent's
  behalf, so the decision costs nothing to defer and would be guesswork now.
- The **`SaveCoordinator`** migration is Phase 2 work by the ADR's own
  sequencing, since no agent can save before then.

---

## Phase 1 — Read-only MCP

- [x] Measure which MCP revision Claude Code, Codex CLI, and OpenFox actually
      send; record it in ADR-012 §4.2. **Result:** Codex CLI 0.149.0 asks for
      `2025-06-18`, Claude Code 2.1.239 asks for `2025-11-25`, both through the
      `initialize` handshake; OpenFox unmeasured. Handshake era only.
- [x] Versioned schema source (`AgentToolCatalog`): the bridge's `tools/list`,
      the app's dispatch, and the tests all read one value.
- [x] SwiftPM executable target for `maruedit-mcp`.
- [ ] Universal build, bundle placement, nested signing, notarization check, CI
      launch test — packaging work, deferred with the rest of release
      engineering until the interface is worth shipping.
- [x] Private `agent.call` envelope over the ADR-011 socket: request ids,
      cancellation, connection identity, grant generation, error mapping,
      framing and fuzz tests.
- [x] Endpoint per instance behind a locked registry; discovery fails closed
      with two live instances; `--instance` selects. Sockets live in a short
      directory of their own: the obvious layout was 108 characters and could
      never have bound.
- [x] Token file, `LOCAL_PEERCRED` check, `--pair` flow, non-modal approval
      surface, rate limiting, connected-client indicator, audit log.
- [x] Read tools: `list_documents`, `list_editors`, `read_document`,
      `get_outline`, `search_documents` (literal, open buffers), `get_selection`.
- [x] Off-main execution with bounds.
- [ ] Edit-handler latency harness — needs a synthetic-keystroke driver that
      does not exist yet; the bounds it would measure are in place.

## Phase 2 — Revision-gated writes

- [x] Bounded anchor minting and digest validation: mutually exclusive request
      forms, 32 per call, 256 per connection, invalidated by any text revision
      change and by disconnect.
- [x] `apply_edits`: strict snapshot on both counters, atomic application, three
      ordered conflict outcomes, undo labelling, LF enforcement, edit-time
      encoding representability.
- [x] Non-writable document states — binary, read-only, view mode.
- [x] Split-pane undo ownership: writes to a document shown in more than one
      pane are refused with `document.multiple_panes`, which is the honest half
      of the ADR's choice. Coordinated per-document undo history remains the
      alternative if the refusal proves annoying in practice.
- [x] `set_selection` and `reveal` with both preconditions.
- [x] Review mode, immutable proposals, retained-state budgets, diff banner.
- [x] `SaveCoordinator`: one machine, every entry point on it — human Save,
      Save As, Save All, save-and-close, agent save. Plan / prepare / fence /
      commit / finalize, with the human superseding an agent save that is still
      preparing and a late human save running immediately after.
- [x] `save_document` commits for real, with revision preconditions checked
      atomically before the write.
- [x] The false-clean bug is gone: what is recorded as saved is the snapshot
      that was written, and metadata that moved after planning leaves the
      document format-dirty.

  Two clauses of ADR-012 §6.5 were falsified by implementing them, and the ADR
  now records both: revision preconditions belong to the requester rather than
  the machine, and the commit runs off-main only where nothing is sequenced
  behind it.

## Phase 3 — Scoped app control

- [x] Authorized directory roots with descriptor-relative containment:
      `openat` with `O_NOFOLLOW` at every component, and a component that fails
      is classified by asking the filesystem what it is rather than by guessing
      from `errno` — a symlinked directory reports `ENOTDIR`, not `ELOOP`.
- [x] `open_document`, with an fd-based loader so a verified path is never
      reopened. Roots are empty by default, which makes it unavailable rather
      than permissive.
- [x] `run_command`, default-deny per command definition. `CommandContext` still
      carries no explicit target, so only commands whose effect does not depend
      on which window is key are exposed, and the flag is named
      `isSafeForAgentsRegardlessOfTarget` to keep that honest.
- [ ] Explicit targets in `CommandContext` — a real refactor of every command,
      deferred until more than a handful of commands need exposing.
- [ ] Regular-expression search once it can be bounded (OQ-8).

## Phase 4 — Change awareness

- [x] Resource surface: opaque `maruedit://document/<id>` URIs, `resources/list`,
      `resources/read` returning text and both revisions together.
- [x] Coalesced URI-only change notifications: the app pushes an event, the
      bridge forwards `notifications/resources/updated`. The notification
      carries no revision on purpose — a pushed number could be stale by the
      time it lands.

## Phase 5 — Persistent grants and second adapter

- [x] Persistent per-configuration trust, to the extent this trust model
      supports it: a paired credential survives a restart and can be marked
      "skip approval next time". Its *grant* still freezes at each connection,
      and the session token is new every launch, so remembering a pairing is
      not remembering a session.
- [x] Revocation and stale-endpoint regression tests, including that revoking a
      credential cuts off its live connections.
- [ ] A real isolation boundary for unattended trust — signed helper plus a
      Keychain ACL bound to its code signature, or user-presence-bound keys.
      Blocked on OQ-1 and, as ADR-012 P9 says, on the fact that same-UID is one
      trust domain no matter what this layer does.
- [ ] Sandbox/App Group decision — a product decision, not code.
- [ ] Evaluate ACP client mode: it needs an agent-conversation UI inside
      MaruEdit, which is a far larger product commitment than an automation
      interface.

---

## Applied from the first implementation review (2026-08-23)

Seventeen findings against roughly 8000 lines of new Swift. The ones that
mattered, and what they were:

- **Two crashes reachable by an approved client.** `Int(1e300)` and
  `UInt64(-1)` trap rather than failing, and every revision and offset field
  went through them. Numeric reads are total now, with the conversions in one
  place and fuzzed.
- **`SIGPIPE`.** Writing to a socket whose peer just quit terminates the
  process by default, taking unsaved work with it. Every socket sets
  `SO_NOSIGPIPE`, and writes have a timeout so a peer that stops reading cannot
  freeze the editor either.
- **The authorization frame was being read as a call result.** The bridge
  treated the state frame the app sends after hello as the answer to the first
  call, so an approved call reported "pending" while the app went ahead and ran
  it — and pairing could never complete at all. Authorization frames are state;
  the app answers every call with a reply, including refusals.
- **A ⌘S could be silently dropped.** `saveSynchronously` returned
  `.inProgress` when an agent save was in flight, throwing the human's save
  away — the exact failure the human-first rule exists to prevent. It is queued
  and runs when the current save unwinds.
- **One Approve button granted everything.** Capabilities are separate now —
  reading, editing, cursor movement, saving, opening files, running commands —
  Approve grants reading only, and the write mode is the human's choice rather
  than the caller's. An agent asking to apply directly gets review unless the
  grant says otherwise.
- **`grantGeneration` was written and never read**, so a revocation during a
  suspended read or save arrived too late to matter. Grants are stamped at
  dispatch and re-checked before anything sensitive is returned or committed.
- **Authorized folders were process-wide**, so a folder granted to one
  configuration authorized every connection. They live on the grant.
- **A typo was destructive**: any `mode` except exactly `"review"` applied
  immediately. Unknown modes are refused.
- **`idempotencyKey` was advertised and never implemented.** It is implemented,
  bounded, and explicitly does not survive a reconnect.
- **`read_document` re-read the buffer after its await** to mint anchors, so
  offsets validated against one string got digests from another — and a
  shortened document could throw outright.
- A file that was deleted or moved is a save conflict, not something to
  recreate. Edit marks are transformed and extended rather than ignored, and
  undo restores them. Resources are no longer advertised while the bridge can
  only receive events during a call.

One finding was **not** applied: the claim that the transaction primitive
writes un-canonicalized text into storage. `AutomationEdit` canonicalizes at
construction, so every replacement is LF before it reaches text storage; a test
covers it.

---

## Open questions that gate work

- **OQ-1** — credential format, rotation, and what binds a credential to one
  program for unattended persistent grants. Gates Phase 5, not Phase 1.
- **OQ-2** — tracked anchors. Gates nothing; strict snapshot ships first.
- **OQ-8** — how regular-expression search gets a real bound. Gates regex search
  in Phase 3.
