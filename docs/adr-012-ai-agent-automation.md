# ADR-012: AI Agent Automation Interface

- Status: Proposed
- Date: 2026-08-22
- Supersedes: ADR-011 (External Control API)
- Scope: How third-party AI coding agents drive a running MaruEdit process

## 0. What changed since ADR-011

ADR-011 asked "how do we let an outside process control MaruEdit?" and answered
it well at the transport and trust layers. It did not ask who that outside
process actually is. In practice it is one of a handful of AI agents —
Claude Code, Codex CLI, OpenFox, and their successors — and every one of them
already speaks a protocol. A bespoke JSON dialect on a Unix socket means every
agent needs a MaruEdit-specific client before it can do anything, which is the
one requirement none of them will satisfy.

This ADR keeps ADR-011's security posture and its shared-automation-layer
refactor, replaces its public wire protocol with MCP, and re-derives the method
catalog from what agents actually get wrong when they edit text.

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
Requests: the server returns `resultType: "input_required"` and the client
retries with `inputResponses`. Roots, Sampling, and Logging are deprecated.
Transports are stdio and Streamable HTTP.

All three named target agents are MCP clients today: Claude Code
(`claude mcp add --transport stdio|http`), Codex CLI (`mcp_servers` in
`~/.codex/config.toml`, stdio default plus remote Streamable HTTP), and OpenFox
(`openfox mcp add`, `--transport stdio|http|sse`).

**ACP** (Agent Client Protocol) is the editor → agent direction: the editor is
the client, the agent runs as a subprocess, and the editor supplies the UI. It
shipped in Zed 1.0 (April 2026), is built into JetBrains IDEs, and has a public
agent registry with 50+ entries. Its `fs/read_text_file` and `fs/write_text_file`
methods exist for exactly one reason: so the agent reads *unsaved buffer state*
rather than disk, and so the editor can render the write as a reviewable inline
diff.

The two are complementary, not competing. MCP is how an agent reaches into an
editor. ACP is how an editor hosts an agent.

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

That gap is the design opportunity. It is also the part an editor — and only an
editor — can actually fix, because the editor is the process that owns the text.

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

**P9 — Same user is not same trust.**
Unchanged from ADR-011, and the reasoning is stronger now: the connecting
process is an autonomous agent acting on instructions that may have come from a
web page, an issue tracker, or the very document it is editing.

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
| R3 | Every document carries a monotonic revision; every write declares `baseRevision` | P3 |
| R4 | Stale writes fail without mutating anything, and return the fresh state | P3, P5 |
| R5 | Reads hand back verifiable anchors; writes may address by anchor | P4 |
| R6 | A multi-part edit applies atomically or not at all | P6 |
| R7 | One tool call is one undo entry, labelled with the calling client | P6 |
| R8 | The human can require review of agent edits, and can revoke mid-session | P1, P6 |
| R9 | Human edits always win; the agent is never allowed to block the UI | P1 |
| R10 | The public protocol is MCP, usable with no MaruEdit-specific client code | P7 |
| R11 | Partial reads (line ranges, search, outline) are cheaper than full reads | P8 |
| R12 | Encoding, line endings, and BOM survive every agent edit unchanged | P2 |
| R13 | Off by default; per-client, capability-scoped, revocable grants; no TCP | P9 |
| R14 | No filesystem, shell, or subprocess primitive is exposed | P9, P10 |
| R15 | Every agent operation is auditable in the app | P9 |

R12 deserves emphasis in a MaruEdit-specific document. A large share of the
target user base edits Shift_JIS and EUC-JP files with CRLF endings. An agent
that writes such a file through a naive UTF-8 filesystem write corrupts it
silently. Routing the edit through MaruEdit is not merely more convenient — it
is the difference between a correct and a destroyed document.

---

## 4. Decision

MaruEdit exposes an **MCP server** as its public AI automation surface.

1. The wire protocol is MCP, revision 2026-07-28, negotiating down to
   2025-06-18 for older clients.
2. The transport is stdio, provided by a small bridge executable shipped inside
   `MaruEdit.app`. The bridge holds no protocol state and no business logic.
3. The bridge reaches the running app over the local Unix domain socket
   specified in ADR-011 §3, which becomes a private, versioned, authenticated
   internal channel rather than a public API.
4. All editor semantics live in one `@MainActor` automation service, shared with
   the existing macro engine, exactly as ADR-011 §12 proposed.
5. The first shipped phase is read-only. Writes ship only once revisions,
   anchors, atomic apply, undo boundaries, and the review gate exist.
6. MaruEdit does **not** implement ACP in v1. It is revisited in §11 as the
   second adapter over the same core.

```text
Claude Code / Codex CLI / OpenFox            (MCP client)
        │  stdio · JSON-RPC · MCP 2026-07-28
        ▼
maruedit-mcp                                  (stateless bridge, in the bundle)
        │  AF_UNIX SOCK_STREAM · 0600 · length-prefixed JSON · session token
        ▼
MaruEdit.app
        ├── AgentControlService                (auth, grants, rate limits, audit)
        └── EditorAutomationService  @MainActor (the only place semantics live)
                  ▲
                  └── MacroCommandBridge        (existing maru.* JavaScript API)
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

The bridge must not receive the session token through `argv` — process
arguments are readable by other processes on the machine. It reads the token
from the `0600` endpoint file itself. If MaruEdit is not running, the bridge
still starts and answers `tools/list` from a static catalog, and returns
actionable tool errors ("MaruEdit is not running") rather than failing to
launch, so the agent's tool list does not flicker in and out of existence.

### 4.2 Statelessness

The 2026-07-28 revision removed protocol sessions. This fits the design rather
than fighting it: the durable state — documents, revisions, anchors, pending
reviews — lives in MaruEdit, and every handle MaruEdit mints (`documentId`,
`anchorId`, `reviewId`) is passed back as an ordinary tool argument. Handles are
opaque, process-lifetime-scoped, and validated against the caller's grant on
every call, per the spec's own guidance on stateful tools.

---

## 5. Tool catalog

Tool names are short because they are re-sent in every prompt (P8). Clients
namespace them by server, so `read_document` reads as `maruedit / read_document`
at the call site.

Every tool declares an `outputSchema` and returns `structuredContent`. Every
recoverable failure is a tool execution error (`isError: true`) whose text names
the cause *and* the state needed to retry, never a bare JSON-RPC error (P5).

### 5.1 Orientation

**`list_documents`** — annotations: read-only.

```jsonc
// → {}
// ← structuredContent
{
  "documents": [
    { "documentId": "doc_7f3a", "displayName": "notes.txt",
      "path": "/Users/x/notes.txt", "windowId": "win_1",
      "isActive": true, "dirty": true, "revision": 412,
      "lines": 1840, "bytes": 96431,
      "encoding": "Shift_JIS", "lineEnding": "CRLF", "bom": false,
      "diskState": "divergent",
      "selection": { "line": 220, "column": 5, "hasSelection": false } }
  ]
}
```

`diskState` is one of `clean`, `divergent` (buffer differs from disk),
`missing`, `externallyChanged`. It is how an agent learns that reading the path
with its own filesystem tool would give it the wrong text (P2).

**`get_outline`** — read-only. Returns the existing `OutlineModel` structure:
heading text, level, line. A 40-line map of a 40,000-line document.

**`search_documents`** — read-only. Literal or regular-expression search over
one document, all open documents, or (capability-gated) a folder, returning
`{ documentId, line, column, lineText, contextBefore, contextAfter }`. This is
the tool that prevents "read the whole file to find one function" (P8, R11).

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
  "truncated": false,
  "text": "…",
  "anchors": [ { "anchorId": "a_9c21", "startLine": 220, "endLine": 224,
                 "digest": "sha256:8f2c…" } ]
}
```

Text is always the buffer, never disk (R1, R2). `revision` is mandatory in the
response because it is the input to every subsequent write (R3). Omitting the
line range reads the whole document, subject to `maxBytes` and an explicit
`truncated` flag — a truncated read is never silently truncated (P5).

**`get_selection`** — read-only. Returns each selection as line/column *and*
UTF-16 offset, plus the selected text up to a bound. Line/column is what models
reason well about; UTF-16 offsets are what `maru.*` and `NSRange` already use,
and both are given so neither side has to convert.

### 5.3 Writing

**`apply_edits`** — the core of the whole design. Annotations: not read-only,
not idempotent, destructive.

```jsonc
// →
{
  "documentId": "doc_7f3a",
  "baseRevision": 412,
  "label": "fix typo in section 3",
  "mode": "review",
  "edits": [
    { "anchorId": "a_9c21", "expectDigest": "sha256:8f2c…",
      "text": "corrected paragraph\r\n" },
    { "range": { "startLine": 900, "startColumn": 1,
                 "endLine": 902, "endColumn": 1 },
      "expectText": "old three lines…",
      "text": "new text\r\n" }
  ]
}
```

Semantics, each one traceable to a failure mode in §1.1:

- **Atomic.** Edits are validated against the document as a whole, then applied
  in one transaction. A single bad anchor fails the entire call and mutates
  nothing (R6). No more half-applied patches.
- **Revision-gated.** `baseRevision` mismatch fails before any validation (R3).
- **Anchor- or range-addressed.** `anchorId` is the preferred form: MaruEdit
  minted it, MaruEdit tracks it across intervening edits, and `expectDigest`
  proves the region is still what the agent read. Ranges are accepted for
  positions the agent computed itself, with `expectText` as the equivalent
  guard. Neither form requires the model to reproduce surrounding text exactly
  (P4).
- **Teaching failures.** On conflict the error carries the current revision, the
  current text of each failed region, and fresh anchors for it — everything the
  agent needs to get it right on the next call without re-reading the file (P5).
- **One undo entry**, named `"claude-code: fix typo in section 3"` (R7). ⌘Z is
  the universal reject button.
- **Line endings and encoding are the document's**, not the payload's. Submitted
  `\n` is normalised to the document's ending; the document's encoding is never
  changed by an edit (R12).
- **`mode`** is `apply` or `review`, bounded by the client's grant. `review`
  returns immediately with `{ "status": "pending", "reviewId": "rev_2b" }` and
  shows a native diff in MaruEdit; it never blocks the agent's tool call while a
  human decides (R9).

**`review_status`** — read-only. `{ reviewId }` → `pending` / `applied` /
`rejected` / `expired`, with the resulting revision when applied. The
server-minted-handle pattern the 2026-07-28 spec prescribes for cross-call
state.

**`set_selection`** / **`reveal`** — move the human's cursor and scroll to a
line. Small tools with outsized value: "here is what I changed" is a selection,
not a paragraph of prose.

**`save_document`** — `{ documentId, expectRevision }`. Never implicit. Saving
runs the existing save path, which means existing external-change detection,
encoding preservation, and conflict handling apply unchanged.

**`open_document`** — `{ path }`, capability-gated. Routes through the normal
document lifecycle so the file arrives with correct encoding detection.

**`run_command`** — `{ commandId }`, default-deny. A command is reachable only
if its registry definition is explicitly marked agent-exposed and the client
holds `commands.run`. Registering a command must never make it remotely
invocable (unchanged from ADR-011 §9.7).

### 5.4 Deliberately absent

No `read_file`, `write_file`, `list_directory`, `run_shell`, `run_external_command`,
or network tool. Every agent that will connect already has those, better. What no
agent has is a correct view of an unsaved Shift_JIS buffer that a human is
typing into — that, and only that, is what MaruEdit should sell (R14).

`external.*` commands stay unreachable in v1 even behind a capability. They
would add no capability the agent lacks while making the audit trail ambiguous
about which process did what.

---

## 6. Concurrency model

One authority, optimistic concurrency, no locks.

- Every document holds `revision: UInt64`, incremented by any mutation from any
  source — human keystroke, macro, agent, reload, undo.
- Reads return the revision. Writes declare `baseRevision`. Mismatch → rejection,
  never a merge attempt (P3). Text merge is the agent's job; it has a model, and
  MaruEdit's guess would be worse.
- Anchors are invalidated by edits that destroy their range, and return
  `anchor_stale` with the surrounding current text.
- Operations are serialized on the main actor per document. Permission checks
  happen before main-actor dispatch, so an unauthorized call never reaches the
  editor at all.
- **No writer lease.** ADR-011 proposed a one-writer control lease; it is
  dropped. A lease adds a lifecycle to leak, blocks legitimate multi-agent use,
  and solves nothing that `baseRevision` does not already solve. Two agents
  racing is the same problem as one agent racing a human, and it has the same
  answer: the loser is told exactly what changed.
- The human is never blocked, never prompted synchronously by an agent call, and
  never has an edit rejected because an agent was mid-flight (P1, R9).

---

## 7. Human-in-the-loop

Four modes per granted client, chosen by the human, changeable at any time:

| Mode | Reads | Writes |
|---|---|---|
| `off` (default) | — | — |
| `read` | yes | rejected |
| `review` | yes | queued as a diff the human accepts or rejects |
| `auto` | yes | applied immediately, still one undo entry each |

Surfaces required before writes ship:

- A status-bar indicator naming every connected client, with a one-click
  disconnect. If a user cannot tell an agent is attached, the feature is not
  shippable.
- A review banner with a real diff, per pending `reviewId`, keyboard-operable.
- A session log — timestamp, client, tool, document, revisions, outcome —
  visible in the app, not only in a file (R15).
- Revocation that takes effect on in-flight calls, not just new connections.

MCP's Multi Round-Trip Requests are deliberately *not* used for the review gate.
MRTR asks the agent's user; MaruEdit's user is sitting in front of MaruEdit. The
native surface is both faster and the only one that can show a real diff of the
buffer.

---

## 8. Security model

ADR-011 §9 and §16 carry over. The invariants that change or sharpen:

1. Off by default; no socket exists until the user enables it; never a TCP
   listener (unchanged).
2. Endpoint directory `0700`, socket `0600`, token regenerated per app launch,
   never passed in `argv` or environment (sharpened — the bridge makes this
   concrete).
3. Connecting is not authorization. The first connection from an unknown client
   raises a native approval sheet showing the bridge's executable path and pid
   and the capabilities requested, and the human grants a mode plus a capability
   set that is revocable in Settings.
4. Capabilities are per-client and fine-grained: `documents.read`,
   `documents.write`, `documents.open`, `documents.save`, `selection.read`,
   `selection.write`, `search.folder`, `commands.run`, `clipboard.read`,
   `clipboard.write`.
5. Commands are default-deny at the definition level.
6. No filesystem, shell, subprocess, or network primitive (R14).
7. Document content is untrusted input. MaruEdit never interprets returned text
   as instruction, and no tool exists whose effect depends on document content
   (P10).
8. Rate limits and a frame-size cap apply per client, and exceeding them
   throttles rather than disconnects, so a runaway agent degrades instead of
   flapping.
9. Everything is audited (R15).

The threat that has no technical answer is a *legitimately granted* agent acting
on instructions its operator did not intend. The mitigation is the review mode,
the undo boundary, and the audit log — which is why they are requirements and
not options.

---

## 9. Phased rollout

**Phase 0 — Shared automation core.** Extract `EditorAutomationService`
(`@MainActor`, value-only) out of `MacroCommandBridge`; keep `maru.*` observably
identical; add process-lifetime document/window IDs; add document revisions and
prove that human edits, macro edits, and undo all bump them. No socket, no
bridge, no protocol. *Exit:* macro tests pass unchanged against the extracted
service.

**Phase 1 — Read-only MCP.** Bridge executable; ADR-011 socket and token; the
approval sheet; `list_documents`, `read_document`, `get_outline`,
`search_documents`, `get_selection`; `server/discover` and version negotiation;
status-bar indicator; audit log. *Exit:* `claude mcp add maruedit -- …`, the
equivalent Codex `config.toml` block, and `openfox mcp add` each produce a
working read-only integration with no MaruEdit-specific client code (R10).

**Phase 2 — Anchors and revision-gated writes.** Anchor minting and tracking;
`apply_edits` with atomic application, digest guards, teaching errors, undo
labelling, encoding/line-ending preservation; `set_selection`, `reveal`,
`save_document`; review mode and `review_status`; the diff banner. *Exit:* an
agent can edit a dirty Shift_JIS CRLF document while a human types in it, and
neither loses work (R3, R6, R12).

**Phase 3 — Scoped app control.** `open_document`, `run_command` behind the
default-deny allow-list, clipboard, folder search. *Exit:* no registry command
is reachable merely because it was registered.

**Phase 4 — Change awareness.** Resources for open documents with `ttlMs` /
`cacheScope`, `listChanged` notifications over `subscriptions/listen`, coalesced
document-change events carrying revisions, so a long-lived agent can invalidate
its cache instead of re-reading (P8).

**Phase 5 — Hardening and second adapter.** Sandbox/App Group decision;
revocation and stale-socket regression tests; then evaluate ACP client mode
(§11).

---

## 10. Testing requirements

Beyond ADR-011 §14's protocol-level tests (fragmented reads, malformed frames,
oversized frames, invalid tokens, stale sockets):

- **Live client conformance.** Automated smoke tests that configure and drive
  real Claude Code, Codex CLI, and OpenFox binaries when present, skipping with
  a clear message when absent. A protocol we only test against our own client is
  a protocol we have not tested.
- **Race tests.** Human edit interleaved between an agent's read and write must
  produce a conflict, never a lost keystroke; concurrent `apply_edits` from two
  clients must produce exactly one winner.
- **Atomicity tests.** A batch whose third edit fails leaves the document
  byte-identical.
- **Encoding fidelity.** Shift_JIS, EUC-JP, UTF-8-with-BOM, and CRLF documents
  survive an agent edit round trip byte-identically outside the edited region.
- **Undo tests.** One tool call is one ⌘Z; review rejection restores exactly.
- **Revocation tests.** Grants revoked mid-call take effect on the in-flight
  call.
- **Token-cost regression.** A fixed task on a fixed large document has a
  recorded byte budget for the tool results it returns; regressions are visible.

---

## 11. ACP: the second adapter, not the first

ACP is the right protocol for a different product decision: hosting an agent
*inside* MaruEdit, with a conversation surface, permission pills, and inline
diffs. It reuses this ADR's core — `fs/read_text_file` is `read_document` with a
different envelope, `session/request_permission` is the review gate — so
adopting it later costs an adapter, not a redesign.

It is not v1 because it requires MaruEdit to ship agent-conversation UI, which
is a product commitment far larger than an automation interface, and because it
does not serve the stated goal: third-party agents driving MaruEdit from where
they already live.

Worth noting for later: the concurrency model in §6 is ahead of what ACP
currently specifies. Unsaved-file synchronisation and "has this buffer changed
since the agent read it" are both open questions in that ecosystem. If MaruEdit
implements revisions and anchors first, it has something to contribute upstream.

---

## 12. Open questions

- **OQ-1 — Grant persistence.** Does a grant survive app restart, keyed to the
  bridge's executable path, or must the human re-approve each launch? Re-approval
  is safer; a coding agent restarted twenty times a day makes it intolerable.
- **OQ-2 — Anchor lifetime.** How long does an anchor survive intervening edits
  before it is cheaper to invalidate it? Related to ADR-007's finding that stale
  anchor handling is the hard part of position tracking.
- **OQ-3 — Large documents.** What is the read budget, and does the answer need
  chunking beyond line ranges plus outline plus search?
- **OQ-4 — Folder search scope.** If `search.folder` exists, whose folder — the
  agent's working directory, or MaruEdit's open documents' directories? The two
  disagree more often than expected.
- **OQ-5 — Multiple windows.** Do agents address windows at all, or only
  documents? Documents-only is simpler and probably right.
- **OQ-6 — Untitled documents.** An agent cannot open an untitled buffer by
  path. Is `documentId`-only addressing sufficient, or is there a naming scheme?
- **OQ-7 — Streamable HTTP.** Does a containerised or remote agent ever need to
  reach MaruEdit? If yes, the answer is a separate ADR, not a flag.

---

## 13. Recommendation

Ship the boring, standard thing: an MCP server whose distinguishing feature is
correctness under concurrent human editing.

The differentiator is not the protocol — the protocol should be as unremarkable
as possible so that every agent works on day one. The differentiator is that
MaruEdit is the only writer that knows the buffer is dirty, knows it is
Shift_JIS with CRLF endings, knows the human's cursor is on line 220, can reject
a stale write with a useful explanation, and can make the whole thing one press
of ⌘Z.

Build the shared core, ship read-only, then earn write access.
