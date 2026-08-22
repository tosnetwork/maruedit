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
- [x] `refreshReadOnlyState()` recomputes from all three sources.
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

- [ ] Measure which MCP revision Claude Code, Codex CLI, and OpenFox actually
      send; record it in ADR-012 §4.2.
- [ ] Versioned schema source; generate the bridge catalog, Swift DTOs,
      validation, and conformance transcripts from it. No tool ships before it.
- [ ] SwiftPM executable target for `maruedit-mcp`, universal build, bundle
      placement, nested signing, notarization check, CI launch test.
- [ ] Private `agent.call` envelope over the ADR-011 socket: request ids,
      cancellation, connection identity, grant generation, error mapping,
      framing and fuzz tests.
- [ ] Endpoint per instance behind a locked registry; discovery fails closed
      with two live instances; `--instance` selects.
- [ ] Token file, `LOCAL_PEERCRED` check, `--pair` flow, non-modal approval
      surface with its five states, rate limiting, connected-client indicator,
      audit log.
- [ ] Read tools: `list_documents`, `list_editors`, `read_document`,
      `get_outline`, `search_documents` (literal, open buffers), `get_selection`.
- [ ] Off-main execution with bounds; edit-handler latency exit.

## Phase 2 — Revision-gated writes

- [ ] Bounded anchor minting and digest validation.
- [ ] `apply_edits`: strict snapshot on both counters, atomic application, three
      ordered conflict outcomes, undo labelling, LF enforcement, edit-time
      encoding representability.
- [ ] Non-writable document states; the split-pane undo ownership decision.
- [ ] `set_selection` and `reveal` with both preconditions.
- [ ] `SaveCoordinator` migration of every existing save entry point, then
      `save_document` preflight and the §6.5 commit protocol with its five
      terminal states.
- [ ] Review mode, immutable proposals, retained-state budgets, diff banner.

## Phase 3 — Scoped app control

- [ ] Authorized directory roots with descriptor-relative containment.
- [ ] `open_document`; fd-based loader so a verified path is never reopened.
- [ ] `run_command` with explicit targets in `CommandContext`, or a
      document-independent-only command set.
- [ ] Regular-expression search once it can be bounded (OQ-8).

## Phase 4 — Change awareness

- [ ] Resource surface: document URIs, `resources/list`, `resources/read`.
- [ ] Coalesced URI-only change notifications, per era.

## Phase 5 — Persistent grants and second adapter

- [ ] Persistent per-configuration grants and the isolation boundary they need.
- [ ] Sandbox/App Group decision.
- [ ] Revocation and stale-socket regression tests.
- [ ] Evaluate ACP client mode.

---

## Open questions that gate work

- **OQ-1** — credential format, rotation, and what binds a credential to one
  program for unattended persistent grants. Gates Phase 5, not Phase 1.
- **OQ-2** — tracked anchors. Gates nothing; strict snapshot ships first.
- **OQ-8** — how regular-expression search gets a real bound. Gates regex search
  in Phase 3.
