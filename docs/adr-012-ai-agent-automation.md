# ADR-012: AI Agent Automation Interface

- Status: Proposed
- Date: 2026-08-22 (revised 2026-08-22 after implementation review)
- Relationship to ADR-011: **amends and profiles it, does not replace it**
- Scope: How third-party AI coding agents drive a running MaruEdit process

## 0. What changed since ADR-011

ADR-011 asked "how do we let an outside process control MaruEdit?" and answered
it well at the transport and trust layers. It did not ask who that outside
process actually is. In practice it is one of a handful of AI agents —
Claude Code, Codex CLI, OpenFox, and their successors — and every one of them
already speaks a protocol. A bespoke JSON dialect on a Unix socket means every
agent needs a MaruEdit-specific client before it can do anything, which is the
one requirement none of them will satisfy.

This ADR therefore defines the **AI agent profile** of ADR-011: it re-derives
the public method catalog from what agents actually get wrong when they edit
text, and replaces the public wire protocol with MCP.

ADR-011 remains normative for everything this document does not restate:
transport selection and rejected alternatives (§3), endpoint layout and
permissions (§3.1), framing and message limits (§4.1–4.2), main-actor boundary
and cancellation semantics (§8), the trust-tier argument (§9.6), Command
Registry exposure policy (§9.7), and the security invariants (§16). Where the
two documents disagree, this one wins **only** on the points it explicitly
names in §8.1.

Three things from ADR-011 are dropped outright, with reasons in §6 and §5.4:
the one-writer control lease, the `externalCommands.run` capability, and the
bespoke public method catalog.

---

## 1. Evidence: how AI agents edit documents today (August 2026)

### 1.1 The default is filesystem string replacement

Terminal agents edit by reading a file, proposing `old_string` → `new_string`,
and writing the result back. This is fragile in ways that are now
well-documented: whitespace mismatches, an anchor that appears twice, a closing
brace that captures the wrong block, and a model cache that no longer matches
disk. The visible symptoms are the "string to replace not found" and "file
unexpectedly modified" classes of error, and each failure costs a retry
round-trip. Tooling has grown up specifically to work around it — content-hashed
line anchors, apply-model services that repair broken patches — which is
evidence of a real defect, not a solved problem.

Stale reads compound. When one tool holds a copy of a file from earlier in a
session and a second tool (or a human) changes it, the first tool writes over
the newer state. Nothing in the filesystem tells it not to.

### 1.2 Two protocols won, in opposite directions

**MCP** (Model Context Protocol) is the agent → tool direction. The current
revision is **2026-07-28**, and it is a substantial redesign: the
`initialize`/`initialized` handshake is gone, protocol-level sessions and
`Mcp-Session-Id` are gone, every request carries its version and client
identity in `_meta`, servers implement `server/discover`, list results carry
`ttlMs`/`cacheScope`, and servers that need cross-call state are told to mint
explicit handles and accept them as ordinary tool arguments. Server-initiated
requests (elicitation, sampling, roots) were replaced by Multi Round-Trip
Requests. Roots, Sampling, and Logging are deprecated. Transports are stdio and
Streamable HTTP.

All three named target agents are MCP clients today: Claude Code
(`claude mcp add --transport stdio|http`), Codex CLI (`mcp_servers` in
`~/.codex/config.toml`, stdio default plus remote Streamable HTTP), and OpenFox
(`openfox mcp add`, `--transport stdio|http|sse`). **Which protocol revision
each of them actually speaks today is an unmeasured fact, and §4.2 makes
measuring it a Phase 1 deliverable rather than an assumption.**

**ACP** (Agent Client Protocol) is the editor → agent direction: the editor is
the client, the agent runs as a subprocess, and the editor supplies the UI. It
shipped in Zed 1.0 (April 2026), is built into JetBrains IDEs, and has a public
agent registry with 50+ entries. Its `fs/read_text_file` and `fs/write_text_file`
methods route file access through the client, which *permits* an editor to serve
unsaved buffer state and to render a write as an inline diff. The protocol does
not require either behavior; both are client implementation choices that the
major clients have made.

The two protocols are complementary, not competing. MCP is how an agent reaches
into an editor. ACP is how an editor hosts an agent.

### 1.3 Editors already expose themselves over MCP

JetBrains ships an integrated MCP server (2025.2+) with a Settings pane listing
which tools are exposed. Visual Studio has one. Neovim has several community
servers that bridge into the running instance over its existing msgpack-RPC
socket. Claude Code's JetBrains integration reads the current selection and the
active file path as per-prompt context and renders proposed changes in the IDE's
native diff viewer.

The pattern is settled: **a small stdio MCP process bridges into the already-running
editor over the editor's own local IPC channel.** That is precisely the shape
ADR-011's Unix socket should take — as a private transport, not as the public
protocol.

### 1.4 What the standards still do not solve

The ACP repository carries an open discussion on unsaved-file synchronisation,
and Zed carries an open issue titled "Agents should check if files/buffers have
been modified since their last read." Neither MCP nor ACP defines optimistic
concurrency for text. Nobody has standardised revisions, conflict rejection, or
atomic multi-edit application.

That gap is the design opportunity, and it is the part an editor — and only an
editor — can fix, because the editor is the process that owns the text.

---

## 2. First principles

Everything below is derived from these. Where a later decision looks arbitrary,
it should trace back to one of them.

**P1 — The human is at the keyboard; the agent is not.**
A document under agent control has two writers with wildly different latency.
The human's edit is a keystroke; the agent's edit is a round trip through a
model. The human must never wait for, be blocked by, or lose work to the agent.

**P2 — While a buffer is dirty, disk is a stale copy.**
MaruEdit holds the only authoritative text for an unsaved document, and untitled
documents have no path at all. Any interface that routes agent edits through the
filesystem is wrong by construction for the case that matters most.

**P3 — Every agent write is based on a read that has already expired.**
The model's "current contents" is a snapshot from seconds or minutes ago. The
correct primitive is therefore optimistic concurrency: writes declare the state
they were computed against, and the authority rejects them if that state moved.

**P4 — Addressing text by fuzzy string match is a probabilistic join.**
The editor knows exact offsets. Making the model re-derive a location by quoting
surrounding text converts a lookup the editor could do exactly into a guess the
model does approximately. Hand out verifiable addresses instead.

**P5 — A failed operation should teach the caller how to succeed.**
An agent retries automatically. A bare "not found" produces a blind retry loop;
a response carrying the current revision and the actual text at the target
produces a correct second attempt. MCP's own guidance says the same: tool
execution errors exist so models can self-correct.

**P6 — An edit the human cannot review or reverse is a liability.**
Undo granularity and diff review are not polish; they are what make it safe to
let a non-deterministic process write into a document.

**P7 — Interop only counts at zero client cost.**
If integrating MaruEdit requires writing a client, it will not happen. The
measure of success is a single `claude mcp add` / `codex` config block /
`openfox mcp add` line.

**P8 — Tokens are the budget.**
Every byte returned is paid for twice — money and latency — and re-reading a
50,000-line file to change one line is the dominant waste in agent editing.
Ranges, outlines, and search results are first-class, not conveniences.

**P9 — Same user is not same trust, and same binary is not same client.**
Unchanged from ADR-011, with one addition this design forced into the open:
every target agent launches the *same* bridge executable, so the connecting
program's path, name, and pid identify nothing at all.

**P10 — Document text is untrusted input.**
An agent reading a MaruEdit document may read text that tries to instruct it.
MaruEdit cannot stop the agent from being persuaded, but MaruEdit must never
itself act on content it returns, and every privileged operation must be gated
by a grant the human made out-of-band.

---

## 3. Requirements

Derived from §2, in the order they must be satisfied.

| # | Requirement | From |
|---|---|---|
| R1 | Agents reach documents through the editor, never through disk | P2 |
| R2 | Reads report authoritative buffer text plus dirty/disk-divergence state | P2 |
| R3 | Every document carries a monotonic text revision; every write declares `baseRevision` | P3 |
| R4 | Stale writes fail without mutating anything, and return the fresh state | P3, P5 |
| R5 | Reads hand back digest-verifiable anchors; writes may address by anchor | P4 |
| R6 | A multi-part edit applies atomically or not at all | P6 |
| R7 | One tool call is one undo entry, labelled with the calling client | P6 |
| R8 | The human can require review of agent edits, and can revoke mid-session | P1, P6 |
| R9 | Human edits always win; no agent call blocks typing or opens a modal | P1 |
| R10 | The public protocol is MCP, usable with no MaruEdit-specific client code | P7 |
| R11 | Partial reads (line ranges, search, outline) are cheaper than full reads | P8 |
| R12 | Protocol text is canonical LF; the document's encoding, line-ending style, and BOM are never changed by an edit | P2 |
| R13 | Off by default; per-client, object-scoped, revocable grants; no TCP | P9 |
| R14 | No general filesystem, shell, or subprocess primitive is exposed | P9, P10 |
| R15 | Every agent operation is auditable in the app | P9 |
| R16 | Selections are addressed per editor pane, with their own revision | P1 |
| R17 | No tool call may depend on a synchronous human decision to return | P1, R9 |

R12 deserves emphasis in a MaruEdit-specific document. A large share of the
target user base edits Shift_JIS and EUC-JP files with CRLF endings. An agent
that writes such a file through a naive UTF-8 filesystem write corrupts it
silently. Routing the edit through MaruEdit is not merely more convenient — it
is the difference between a correct and a destroyed document.

R12 also states the contract precisely, because the obvious phrasing is wrong.
`Document.content` is always LF-normalized internally and `save()` re-applies
`Document.lineEnding` on write (`Sources/MaruEditApp/Document.swift`). The
protocol therefore carries **LF only**; a payload containing CR is rejected, not
translated, because silently inserting `\r` would put literal control characters
into the buffer. Line-ending style is document metadata that an agent can read
and that only `save` acts on. Mixed-ending documents (`LineEndingState.mixed`)
still require the existing human choice before any save, so they are excluded
from byte-identity guarantees (§10).

---

## 4. Decision

MaruEdit exposes an **MCP server** as its public AI automation surface.

1. The transport is stdio, provided by a small bridge executable shipped inside
   `MaruEdit.app`.
2. The bridge reaches the running app over the local Unix domain socket
   specified in ADR-011 §3, which becomes a private, versioned, authenticated
   internal channel rather than a public API.
3. All editor semantics live in one `@MainActor` automation service, shared with
   the existing macro engine, exactly as ADR-011 §12 proposed — but only the
   parts that must touch the editor run there (§6.4).
4. The first shipped phase is read-only. Writes ship only once revisions,
   anchors, the atomic transaction primitive, undo boundaries, and the review
   gate exist.
5. MaruEdit does **not** implement ACP in v1. It is revisited in §11 as the
   second adapter over the same core.

```text
Claude Code / Codex CLI / OpenFox            (MCP client)
        │  stdio · JSON-RPC · one protocol era per connection
        ▼
maruedit-mcp                                  (bridge, in the bundle)
        │  AF_UNIX SOCK_STREAM · 0600 · length-prefixed JSON · peer-cred + token
        ▼
MaruEdit.app
        ├── AgentControlService                (auth, grants, rate limits, audit)
        ├── EditorAutomationService  @MainActor (the only place semantics live)
        │        ▲
        │        └── MacroCommandBridge         (existing maru.* JavaScript API)
        └── off-main workers                   (search, outline, hashing, encode)
```

### 4.1 Why a bridge process rather than an in-app server

An MCP stdio server is *spawned by its client*. A GUI application that is
already running cannot be spawned as anyone's child process, so the app cannot
be the stdio server itself. The alternatives were:

- **Bridge executable (chosen).** Preserves ADR-011's "no network listener"
  invariant, needs no port allocation, no OAuth story, and no firewall prompt.
  Configuration is one line pointing at a path inside the app bundle.
- **Streamable HTTP inside the app.** Rejected for v1. It means binding a
  loopback TCP port from a document editor, inherits MCP's authorization
  expectations, and makes "is anything listening?" a question the user has to
  ask. Reconsider only if remote/containerised agents become a real requirement.
- **Teach every agent a custom protocol.** Rejected under P7.

### 4.2 Protocol revision support is a measurement, not an assumption

MCP 2026-07-28 and MCP 2025-06-18 are different protocol eras, not dialects.
The older era requires `initialize`/`notifications/initialized`, connection-scoped
capability negotiation, and result envelopes without `resultType`; the newer era
forbids the handshake and requires per-request `_meta`. A server that claims to
"negotiate down" between them is really two servers.

Therefore:

- Phase 1 begins by **measuring** which revision each target client actually
  sends today — a one-evening exercise with a logging stub server and the three
  binaries — and records the result in this document.
- The bridge implements **one complete era per connection**, selected on the
  first frame (a `server/discover` or an `initialize` decides it). If two eras
  must ship, they are two explicit adapters over one internal request model,
  each with its own conformance transcript, not a set of conditionals.
- If the measurement shows all three clients on one era, MaruEdit ships that era
  alone and adds the second only when a real client needs it.

This also corrects a claim in the first draft of this ADR: the bridge is **not**
stateless. It holds per-connection protocol state (era, negotiated capabilities,
in-flight request ids). What it holds no state of is *business* state —
documents, revisions, anchors, and proposals live in MaruEdit, and every handle
MaruEdit mints (`documentId`, `editorId`, `anchorId`, `proposalId`) travels back
as an ordinary tool argument, opaque and re-authorized on every call.

### 4.3 The bridge is not an identity

Every target agent launches the same executable at the same path inside the app
bundle. Any grant keyed to that path, or to a process name or pid, is therefore
a grant to *every* agent on the machine and to anyone who runs the bridge by
hand. ADR-011 §9.4 said process names are not identities; this design makes the
consequence concrete.

- The Unix socket path and `endpoint.json` remain **token-free**, exactly as
  ADR-011 §3.1 requires. The session token lives in its own `0600` file inside
  the `0700` endpoint directory. The bridge reads it from that file — never from
  `argv`, which is world-readable via `ps`, and never from the environment.
- On accept, MaruEdit verifies the peer's uid with `LOCAL_PEERCRED`. This proves
  *same user* and nothing more, and is treated as a precondition rather than an
  authorization.
- **Phase 1 authorizes per connection, with no persistent identity.** A new
  connection raises a native approval sheet; the executable path, pid, and any
  client-supplied name are shown as *display only*, clearly labelled as
  unverified. Unapproved connections are rate-limited so that a loop cannot spam
  approval UI.
- Persistent, per-agent grants require an explicit pairing step that issues a
  distinct credential per agent configuration — the agent stores it in its own
  MCP server config, and it is revocable individually. Designing that is
  **OQ-1**, and it blocks any persistent grant, not just convenience.

---

## 5. Tool catalog

Tool names are short because they are re-sent in every prompt (P8). Clients
namespace them by server, so `read_document` reads as `maruedit / read_document`
at the call site.

Every tool declares an `outputSchema` and returns `structuredContent`. Every
recoverable failure is a tool execution error (`isError: true`) whose text names
the cause *and* the state needed to retry, never a bare JSON-RPC error (P5).

### 5.0 Coordinate and text conventions (normative)

These exist because the codebase currently uses both conventions —
`LineIndex` is zero-based, `GrepService` output is one-based — and an
unstated choice here is an off-by-one in every client.

- **Text on the wire is LF-only Unicode.** A payload containing `\r` is rejected
  with `text.carriage_return`. Documents report their `lineEnding` as metadata.
- **Edit addressing is by anchor or by offset.** Offsets are zero-based UTF-16
  code-unit indices into the LF-normalized buffer, half-open `[start, end)`.
  Edits never use line/column, which removes an entire class of off-by-one.
- **Human-facing positions are one-based lines** and one-based UTF-16 columns.
  They appear in `read_document` ranges, search results, outlines, and `reveal`,
  always alongside the corresponding offset.
- **Digests** are SHA-256 over the UTF-8 encoding of the LF-normalized region
  text, printed as `sha256:` plus lowercase hex.

### 5.1 Orientation

**`list_documents`** — annotations: read-only.

```jsonc
// ← structuredContent
{
  "documents": [
    { "documentId": "doc_7f3a", "displayName": "notes.txt",
      "path": "/Users/x/notes.txt",
      "dirty": true, "revision": 412,
      "lines": 1840, "utf16Length": 96431,
      "encoding": "Shift_JIS", "lineEnding": "CRLF", "bom": false,
      "diskState": "divergent",
      "editorIds": ["ed_1a", "ed_1b"] }
  ]
}
```

`diskState` is one of `clean`, `divergent`, `missing`, `externallyChanged`. It
is how an agent learns that reading the path with its own filesystem tool would
give it the wrong text (P2).

Note what is *not* here: a selection. Selection belongs to an editor pane, not
to a document — `MainWindowController` can hold a `secondaryEditorVC` whose
`EditorViewController` owns separate TextKit storage and an independent cursor.
A document displayed in two panes has two selections (R16).

**`list_editors`** — read-only. One entry per open editor pane:
`{ editorId, documentId, windowId, isActive, isPrimaryPane, selectionRevision }`.

**`get_outline`** — read-only. The existing `OutlineModel` structure: heading
text, level, one-based line. A 40-line map of a 40,000-line document.

**`search_documents`** — read-only. Literal or regular-expression search over
one document, all open documents, or an explicitly authorized folder root,
returning `{ documentId, line, column, offset, lineText, contextBefore,
contextAfter }`. This is the tool that prevents "read the whole file to find one
function" (P8, R11). It runs off the main actor with hard bounds (§6.4), and the
folder scope is an explicitly authorized filesystem read, not an exception to
R14 — see §5.4 and §8.

### 5.2 Reading

**`read_document`** — read-only.

```jsonc
// → { "documentId": "doc_7f3a", "startLine": 200, "endLine": 260,
//     "withAnchors": true, "maxBytes": 65536 }
// ← structuredContent
{
  "documentId": "doc_7f3a", "revision": 412, "dirty": true,
  "encoding": "Shift_JIS", "lineEnding": "CRLF",
  "startLine": 200, "endLine": 260, "totalLines": 1840,
  "startOffset": 8123, "endOffset": 11004,
  "truncated": false,
  "text": "…LF-only…",
  "anchors": [ { "anchorId": "a_9c21", "revision": 412,
                 "start": 9040, "end": 9210,
                 "startLine": 220, "endLine": 224,
                 "digest": "sha256:8f2c…" } ]
}
```

Text is always the buffer, never disk (R1, R2), and always LF (R12). `revision`
is mandatory in the response because it is the input to every subsequent write
(R3). Omitting the line range reads the whole document, subject to `maxBytes`
and an explicit `truncated` flag — a truncated read is never silently truncated
(P5).

**`get_selection`** — read-only. `{ editorId }` → each selection as one-based
line/column *and* zero-based UTF-16 offset, the document revision, the
`selectionRevision`, and the selected text up to a bound.

### 5.3 Writing

**`apply_edits`** — the core of the whole design. Annotations: not read-only,
not idempotent, destructive.

```jsonc
// →
{
  "documentId": "doc_7f3a",
  "baseRevision": 412,
  "idempotencyKey": "cc-8f1e-0007",
  "label": "fix typo in section 3",
  "mode": "review",
  "edits": [
    { "anchorId": "a_9c21", "expectDigest": "sha256:8f2c…",
      "text": "corrected paragraph\n" },
    { "start": 40210, "end": 40388,
      "expectDigest": "sha256:11ab…",
      "text": "new text\n" }
  ]
}
```

Semantics, each one traceable to a failure mode in §1.1:

- **Strict snapshot.** `baseRevision` must *equal* the document's current
  revision. There is no "apply anyway if the anchors still match" path in v1;
  §6.2 explains why, and OQ-2 holds the door open for tracked anchors later.
- **Anchors are snapshot handles, not tracked ranges.** An anchor is valid only
  at the revision that minted it. Its value over a raw offset is that the agent
  proves it is editing the region it read by echoing a 32-byte digest instead of
  a paragraph of text (P8).
- **Atomic.** Edits are validated as a set — bounds, overlap, digests, encoding
  representability — and then applied in one transaction. Any failure fails the
  entire call and mutates nothing (R6). Overlapping edits are rejected, not
  merged.
- **Teaching failures.** On conflict the error carries the current revision, the
  current text of each failed region, and fresh anchors for it — everything the
  agent needs to get it right on the next call without re-reading the file (P5).
- **One undo entry**, named `"claude-code: fix typo in section 3"` (R7). ⌘Z is
  the universal reject button. This requires a new transaction primitive; the
  existing `batchReplace` silently drops out-of-bounds ranges, merges overlaps,
  and hard-codes its undo action name, so it cannot back this contract (§9,
  Phase 0).
- **Encoding is enforced at edit time.** If inserted text contains characters
  not representable in the document's encoding, the call fails with
  `encoding.unrepresentable` listing the offending scalars, rather than
  producing a document that cannot be saved without a human conversion decision.
- **`mode`** is `apply` or `review`, bounded by the client's grant. `review`
  returns immediately with `{ "status": "pending", "proposalId": "prp_2b" }` and
  never blocks the tool call while a human decides (R17).
- **`idempotencyKey`** is optional but recommended: a repeated call with the same
  key returns the original outcome instead of creating a second proposal or a
  second edit.

**`review_status`** — read-only. `{ proposalId }` → `pending` / `applied` /
`rejected` / `conflicted` / `expired`, with the resulting revision when applied.

**`set_selection`** / **`reveal`** — `{ editorId, baseSelectionRevision, … }`.
Move the human's cursor and scroll to a line. Small tools with outsized value:
"here is what I changed" is a selection, not a paragraph of prose. The selection
revision precondition exists so an agent cannot yank a cursor the human just
moved (R9, R16).

**`save_document`** — `{ documentId, expectRevision }`, split into preflight and
commit because the existing save path can present modal alerts for external
modification, mixed line endings, and unrepresentable text, and a modal inside a
tool call would violate R17 and can hang an MCP request indefinitely. Preflight
returns a structured outcome — `ok`, `external_change`, `mixed_line_endings`,
`unrepresentable`, `save_as_required`, `read_only` — and only `ok` proceeds to a
non-interactive commit. Anything else is reported to the agent and, where a human
decision is genuinely required, surfaced in MaruEdit as a pending item the human
resolves on their own time.

**`open_document`** — `{ path }`, capability-gated. Routes through the normal
document lifecycle so the file arrives with correct encoding detection.

**`run_command`** — `{ commandId }`, default-deny. A command is reachable only
if its registry definition is explicitly marked agent-exposed and the client
holds `commands.run`. Registering a command must never make it remotely
invocable (unchanged from ADR-011 §9.7). Commands that can present modal UI are
not eligible (R17).

### 5.4 Deliberately absent

No `read_file`, `write_file`, `list_directory`, `run_shell`,
`run_external_command`, or network tool. Every agent that will connect already
has better versions of those. What no agent has is a correct view of an unsaved
Shift_JIS buffer that a human is typing into — that, and only that, is what
MaruEdit should sell (R14).

One honest exception: `search_documents` with a folder scope *is* a filesystem
read primitive. It is bounded rather than general — an explicitly authorized
root, canonicalized, containment re-checked after symlink resolution, symlinks
not followed by default, and a hard cap on matches and bytes returned — and it
is described that way in the approval sheet rather than hidden behind the
phrase "search".

`external.*` commands stay unreachable in v1. The reason is not that agents
already have shell access — a sandboxed or remote agent may not — but that
MaruEdit's curated external commands run with full user authority, and routing
them through an automation grant makes the audit trail ambiguous about which
process caused a subprocess to run. They are deferred and intentionally
unsupported by this profile, not judged capability-equivalent.

---

## 6. Concurrency model

One authority, optimistic concurrency, no locks.

### 6.1 Revisions

Three independent monotonic counters, because they answer different questions
and conflating them makes every precondition either too strict or useless:

- `revision` — document text. Incremented by any text mutation from any source.
- `selectionRevision` — per editor pane. Incremented by cursor and selection
  changes.
- `metadataRevision` — encoding, line-ending style, BOM, file identity,
  read-only state.

Getting text-revision coverage right is Phase 0 work and is not free: today's
mutation paths include the `NSTextView` delegate's `textDidChange`, the
multi-cursor `batchReplace` (which deliberately bypasses that delegate), undo
restoring a whole editor snapshot, reload, encoding change, and direct
assignment to `Document.content` in several places. Phase 0 introduces one
mutation-notification boundary that all of them go through, and audits every
direct assignment.

### 6.2 Writes

- Reads return the revision. Writes declare `baseRevision`, which must be equal.
  Mismatch → rejection, never a merge attempt (P3). Text merge is the agent's
  job; it has a model, and MaruEdit's guess would be worse.
- Strict equality is chosen over "newer revision is fine if the anchors still
  match" because the second rule is only sound if anchors are tracked through
  intervening edits, and tracked anchors need boundary affinity, overlap
  behavior, lifetime, and memory bounds all specified and tested. That is a
  feature, not a footnote (OQ-2). Until then, an agent that loses a race
  re-reads the region it cares about — cheap, because §5.1 gives it search and
  outline instead of a whole-file read.
- Operations serialize on the main actor per document.
- **No writer lease.** ADR-011 proposed a one-writer control lease. Revision
  equality plus a single atomic check-and-apply on the main actor already
  provides lost-update safety, which is what the lease was for. It is not that a
  lease "solves nothing" — it would also give fairness and a clear ownership
  indicator — but those are scheduling and UI problems, and §8's per-client rate
  limits plus the connected-client indicator address them without a lifecycle
  that can leak or block legitimate multi-agent use.

### 6.3 Permission checking

ADR-011 §8.1 requires permission checks before main-actor dispatch; §7 here
requires revocation to affect in-flight calls. Both hold only if the check
happens twice:

1. A cheap authorization check off the main actor, which rejects unauthorized
   calls before they can occupy the editor at all.
2. An atomic re-validation on the main actor, immediately before commit, of the
   credential, the grant generation counter, the target's continued existence,
   and the revision precondition.

The same re-validation runs when a human accepts a pending proposal, because the
grant may have been revoked while the proposal sat in the queue.

### 6.4 Where work runs

`@MainActor` is for target resolution, snapshot capture, and mutation. Nothing
else. Outline construction, regular-expression search, digest computation,
encoding-representability checks, truncation, and JSON serialization run off the
main actor against an immutable snapshot tagged with the revision it was taken
at. In-memory search can scan up to ten million characters per document today,
and `NSRegularExpression` has no execution timeout, so running it on the main
actor would visibly stall typing and break R9.

Every read tool therefore carries explicit bounds — document bytes, pattern
length, match count, context bytes, wall-clock deadline — and returns a
structured `limit.*` error rather than running long.

---

## 7. Human-in-the-loop

Four modes per granted client, chosen by the human, changeable at any time:

| Mode | Reads | Writes |
|---|---|---|
| `off` (default) | — | — |
| `read` | yes | rejected |
| `review` | yes | queued as a proposal the human accepts or rejects |
| `auto` | yes | applied immediately, still one undo entry each |

### 7.1 Proposal lifecycle

A pending proposal is **immutable**: `{ proposalId, documentId, baseRevision,
perEditDigests, normalizedEdits, client, label, createdAt }`. It is never
rewritten, relocated, or merged.

On acceptance, the same atomic check that guards a direct write runs again. If
the document's revision moved while the proposal was pending — the human kept
typing, which they are explicitly allowed to do (P1) — the proposal becomes
`conflicted`, nothing is applied, and the agent must re-propose against the new
revision. Silently applying stored ranges to a document that has moved is the
exact lost-update bug this whole design exists to prevent.

Proposals expire after a bounded time and on document close, and are dropped on
revocation.

### 7.2 Required surfaces

- A status-bar indicator naming every connected client, with a one-click
  disconnect. If a user cannot tell an agent is attached, the feature is not
  shippable.
- A review banner with a real diff, per pending proposal, keyboard-operable, and
  showing the proposal's base revision so a conflicted proposal is legible.
- A session log — timestamp, client, tool, document, revisions, outcome —
  visible in the app, not only in a file (R15).
- Revocation that takes effect on in-flight calls via the grant generation
  counter (§6.3), not just on new connections.

MCP's Multi Round-Trip Requests are deliberately *not* used for the review gate.
MRTR asks the agent's user; MaruEdit's user is sitting in front of MaruEdit. The
native surface is both faster and the only one that can show a real diff of the
buffer.

---

## 8. Security model

ADR-011 §9 and §16 carry over in full and are not restated here.

### 8.1 Where this profile amends ADR-011

1. **Token location.** ADR-011 §3.1's rule stands — `endpoint.json` carries no
   token. This profile adds that the token lives in a separate `0600` file, is
   read by the bridge from that file only, and never appears in `argv` or the
   environment (§4.3).
2. **Peer credentials.** Connections are additionally checked with
   `LOCAL_PEERCRED` for uid equality, as a precondition and not an
   authorization.
3. **Identity.** ADR-011 §9.4's "process names are not identities" is extended:
   because every agent launches the same bundled bridge, *no* property of the
   connecting process may key a persistent grant. Phase 1 is per-connection
   approval only; persistent grants require the pairing design in OQ-1.
4. **Grant scope.** ADR-011's capabilities were per-client only. This profile
   requires them to be object-scoped as well: a grant names the documents,
   window, or authorized directory roots it covers, and states explicitly
   whether documents opened later inherit it. A blanket `documents.read` over
   everything now and in the future is a different and much larger grant than it
   appears.
5. **Writer lease and External Commands** are removed from this profile (§6.2,
   §5.4).
6. **No modal UI** may be reached from any agent-initiated call (R17), which
   constrains both `save_document` and `run_command` exposure.

### 8.2 Capabilities

`documents.read`, `documents.write`, `documents.open`, `documents.save`,
`selection.read`, `selection.write`, `search.folder`, `commands.run`,
`clipboard.read`, `clipboard.write` — each scoped per §8.1(4), each revocable
individually in Settings, each surfaced in plain language in the approval sheet.

### 8.3 Residual risk

The threat that has no technical answer is a *legitimately granted* agent acting
on instructions its operator did not intend — including instructions embedded in
a document it was asked to edit (P10). The mitigation is review mode, the undo
boundary, the object-scoped grant, and the audit log, which is why they are
requirements and not options.

---

## 9. Phased rollout

**Phase 0 — Shared automation core.**
Extract `EditorAutomationService` (`@MainActor`, value-only) out of
`MacroCommandBridge`; keep `maru.*` observably identical. Add process-lifetime
`documentId` / `editorId` / `windowId`. Add the three revision counters and the
single mutation-notification boundary, auditing every existing path that mutates
`Document` — `textDidChange`, `batchReplace`, undo snapshot restore, reload,
encoding change, direct assignment. Build the **validated transaction
primitive** underneath both adapters: bounds and overlap rejection before any
mutation, one undo snapshot, caller-supplied undo label, typed result. Keep the
macro path's existing lenient behavior by adapting it, not by weakening the
primitive. No socket, no bridge, no protocol.
*Exit:* macro tests pass unchanged; revision-source tests cover every mutation
path; the transaction primitive rejects a batch containing one invalid range
without mutating the document.

**Phase 1 — Read-only MCP.**
Measure which MCP revision each target client sends (§4.2) and record it here.
Add the SwiftPM executable target for the bridge, its universal build, bundle
placement, nested code signing, notarization verification, and a CI launch test.
Specify the bridge↔app internal protocol — request ids, cancellation, error
model, caller credential propagation, reconnect — with framing and fuzz tests,
and generate the bridge's static tool catalog from the same schema source as the
app so the two cannot drift. Implement the socket, token file, peer-credential
check, per-connection approval sheet, rate limiting, status-bar indicator, and
audit log. Ship `list_documents`, `list_editors`, `read_document`, `get_outline`,
`search_documents`, `get_selection`, all executing off-main with bounds.
*Exit:* `claude mcp add maruedit -- …`, the equivalent Codex `config.toml` block,
and `openfox mcp add` each produce a working read-only integration with no
MaruEdit-specific client code, and a full-document regex search on a 10 MB
buffer does not measurably affect typing latency.

**Phase 2 — Revision-gated writes.**
Anchor minting and digest validation; `apply_edits` with strict snapshot
semantics, atomic application, teaching errors, undo labelling, LF enforcement,
and edit-time encoding representability checks; `set_selection` and `reveal`
with selection revisions; `save_document` preflight/commit; review mode,
immutable proposals, and the diff banner.
*Exit:* an agent edits a dirty Shift_JIS CRLF document while a human types in
it, and neither loses work; a proposal accepted after the human typed is
reported `conflicted` rather than applied.

**Phase 3 — Scoped app control.**
`open_document`, `run_command` behind the default-deny allow-list with modal-free
screening, clipboard, authorized folder search with containment checks.
*Exit:* no registry command is reachable merely because it was registered.

**Phase 4 — Change awareness.**
Resources for open documents with `ttlMs` / `cacheScope`, `listChanged`
notifications over `subscriptions/listen`, coalesced document-change events
carrying revisions, so a long-lived agent can invalidate its cache instead of
re-reading (P8).

**Phase 5 — Persistent identity and second adapter.**
The OQ-1 pairing design and persistent per-agent grants; sandbox/App Group
decision; revocation and stale-socket regression tests; then evaluate ACP client
mode (§11).

---

## 10. Testing requirements

Beyond ADR-011 §14's protocol-level tests (fragmented reads, malformed frames,
oversized frames, invalid tokens, stale sockets):

- **Live client conformance, versioned.** Automated smoke tests that configure
  and drive real Claude Code, Codex CLI, and OpenFox binaries, recording the
  protocol revision each one negotiated. Skipping when a binary is absent is
  acceptable; not recording the version is not.
- **Race tests.** A human edit interleaved between an agent's read and write
  must produce a conflict, never a lost keystroke; concurrent `apply_edits` from
  two clients must produce exactly one winner; a proposal accepted after an
  intervening edit must report `conflicted`.
- **Atomicity tests.** A batch whose third edit fails leaves the document
  byte-identical, including its undo stack.
- **Encoding and line-ending fidelity.** Shift_JIS, EUC-JP, and UTF-8-with-BOM
  documents survive an agent edit round trip byte-identically outside the edited
  region. CRLF documents keep CRLF on save while the protocol only ever carries
  LF. Payloads containing `\r` are rejected. Text unrepresentable in the target
  encoding is rejected at edit time. Mixed-ending documents are explicitly
  excluded from byte-identity and are covered by their own test asserting the
  existing human choice still gates the save.
- **Modal-freedom test.** No agent-initiated path reaches `runModal()`; asserted
  structurally, not by inspection.
- **Latency tests.** Typing latency under a concurrent full-document search and
  under a large `read_document` stays within the existing input-latency budget.
- **Undo tests.** One tool call is one ⌘Z; review rejection restores exactly.
- **Authorization tests.** Grants revoked mid-call take effect on the in-flight
  call; an unapproved connection cannot spam approval UI; a second bridge process
  gets its own approval rather than inheriting the first one's grant.
- **Token-cost regression.** A fixed task on a fixed large document has a
  recorded byte budget for the tool results it returns.

---

## 11. ACP: the second adapter, not the first

ACP is the right protocol for a different product decision: hosting an agent
*inside* MaruEdit, with a conversation surface, permission prompts, and inline
diffs. Adopting it later costs an adapter rather than a redesign, because the
same core answers both — but the mapping is not free. ACP's file methods are
path-addressed client callbacks, so MaruEdit would need path-to-buffer mapping,
change notification, and the same revision checks applied underneath;
`session/request_permission` authorizes a tool call and is not by itself the
diff-review surface this ADR specifies.

It is not v1 because it requires MaruEdit to ship agent-conversation UI, which
is a product commitment far larger than an automation interface, and because it
does not serve the stated goal: third-party agents driving MaruEdit from where
they already live.

Worth noting for later: the concurrency model in §6 is ahead of what ACP
currently specifies. Unsaved-file synchronisation and "has this buffer changed
since the agent read it" are both open questions in that ecosystem. If MaruEdit
implements revisions and proposals first, it has something to contribute
upstream.

---

## 12. Open questions

- **OQ-1 — Agent pairing (blocking).** What issues a per-agent credential, how
  does the human associate it with "the Claude Code on this machine", and where
  does the agent store it? Blocks every persistent grant; Phase 1 ships
  per-connection approval without it.
- **OQ-2 — Tracked anchors.** Should a later phase allow a write at a newer
  revision when every referenced anchor still validates? Requires boundary
  affinity, overlap semantics, lifetime, and memory bounds, and relates to
  ADR-007's finding that stale-anchor handling is the hard part of position
  tracking.
- **OQ-3 — Grant inheritance.** Does a grant cover documents opened after it was
  made? Inheriting is convenient and quietly enormous; not inheriting means an
  approval sheet per file.
- **OQ-4 — Large documents.** What is the read budget, and does the answer need
  chunking beyond line ranges plus outline plus search?
- **OQ-5 — Proposal expiry.** How long may a pending proposal sit before it is
  dropped, and does an expired proposal notify the agent or only fail its next
  poll?
- **OQ-6 — Untitled documents.** An agent cannot address an untitled buffer by
  path. Is `documentId`-only addressing sufficient in practice for the agents
  that will call?
- **OQ-7 — Streamable HTTP.** Does a containerised or remote agent ever need to
  reach MaruEdit? If yes, the answer is a separate ADR, not a flag.

---

## 13. Recommendation

Ship the boring, standard thing: an MCP server whose distinguishing feature is
correctness under concurrent human editing.

The differentiator is not the protocol — the protocol should be as unremarkable
as possible so that every agent works on day one. The differentiator is that
MaruEdit is the only writer that knows the buffer is dirty, knows it is
Shift_JIS with CRLF endings, knows which pane the human's cursor is in, can
reject a stale write with a useful explanation, and can make the whole thing one
press of ⌘Z.

Build the shared core, ship read-only, then earn write access.
