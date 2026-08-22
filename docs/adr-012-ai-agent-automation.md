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
`Mcp-Session-Id` are gone, every request carries its protocol version in
`_meta` and *should* carry client identity there, servers identify themselves in
each result's `_meta`, servers implement `server/discover`, list results carry
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
`save()` re-applies `Document.lineEnding` on write, and file loading normalizes
to LF (`Document.open` runs `LineEndingDetector.normalize`). The protocol
therefore carries **LF only**; a payload containing CR is rejected, not
translated, because silently inserting `\r` would put literal control characters
into the buffer. Line-ending style is document metadata that an agent can read
and that only `save` acts on. Mixed-ending documents (`LineEndingState.mixed`)
still require the existing human choice before any save, so they are excluded
from byte-identity guarantees (§10).

**The LF invariant is currently a loading invariant, not a model invariant, and
Phase 0 has to close that gap before any of this is true.** A CR can already
exist in a buffer today. Rejecting CR on the write path does not by itself let
`read_document` promise LF-only text, and normalizing text on the *response*
path is not an option, because it would invalidate the UTF-16 offsets and
digests returned alongside it.

**Decision.** MaruEdit canonicalizes CRLF and lone CR to LF at every ingress,
*before* the mutation reaches text storage — not in `textDidChange`, which runs
after offsets and undo state already reflect the unnormalized text. The MCP
boundary is stricter: it *rejects* CR rather than normalizing it, so an agent is
told its payload was wrong instead of having it silently rewritten.

That decision has **two** visible consequences, and both are deliberate:

1. `maru.document.setText` with a CRLF string now stores LF. Phase 0's
   "observably identical" rule carves this out rather than blocking on it.
2. The Insert Control Code command currently offers `CR 0D` in its picker. A
   buffer that cannot hold a CR cannot honestly offer to insert one, so that
   entry goes away. The inconsistency already exists today: a file containing
   lone CRs is normalized on load, so the code point survives typing but not a
   round trip.

   **Removing the row is not the change — the picker maps a row *index* to a
   byte value**, special-casing only the last row as `DEL`. Deleting a row would
   make `SO` insert CR, shift every C0 value after it, and make the final row
   insert `US`. The command must be converted to value-backed entries first, and
   `insertControlCode(_:)`, which today accepts `0x0D` from any caller, must
   reject it. Phase 0 tests the mapping of `SO`, `US`, and `DEL` explicitly,
   because a silent off-by-one here would corrupt user data in a command whose
   entire purpose is byte precision.

The alternative — keeping CR insertion as an exception — was rejected because a
buffer invariant with an exception is not an invariant, and every offset,
digest, and anchor guarantee in this document rests on it. If the maintainer
values the CR entry more than the invariant, that reverses this whole section,
not just the picker.

The ingress inventory Phase 0 must cover, from the current code:

| Ingress | Today | Path |
|---|---|---|
| File open | normalized | `Document.open` → `LineEndingDetector.normalize` |
| Insert File | normalized | `Document.normalizedText(contentsOf:)` |
| `Document.init` / recovery restore | **raw** | content stored verbatim |
| New document from template | **raw** | `Document.fromTemplate` → `ProfileFilePolicy.loadTemplate` |
| Insert Template command | **raw** | `insertTemplateContents` → `NSTextView` insertion |
| Macro `setDocumentText` | **raw** | `MacroCommandBridge` → `batchReplace` |
| Multi-cursor paste, box paste, conversion pipeline | **raw** | `EditorSelectionCommands` → `batchReplace` |
| Typing, standard paste, IME commit, text drop | **raw** | `NSTextView` mutation → `textDidChange` copies verbatim |
| Find / Replace and Replace All | **raw** | `EditorSearch` writes `NSTextStorage` directly, bypassing `batchReplace` |
| External command `replaceSelection` / new document | **raw** | `ExternalCommandController` → `batchReplace` |
| Generated grep-result document | **raw** | direct assignment to `Document.content` |

There is no snippet-expansion feature to cover; completion is word completion
and inserts no multi-line text. Phase 0 introduces one pre-mutation
canonicalizer that both the AppKit-originated paths and the programmatic
transaction primitive call, and §10 tests every row above.

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
  first frame. Selection is by envelope, not by method name: a frame carrying
  the modern protocol-version `_meta` selects the modern adapter whatever the
  method is, and an `initialize` selects the legacy one. `server/discover` is
  optional in the modern era — a conforming client may open with an ordinary
  `tools/list` or `tools/call` — so an adapter that waits for discovery would
  reject valid clients. If two eras must ship, they are two explicit adapters
  over one internal request model, each with its own conformance transcript, not
  a set of conditionals.
- If the measurement shows all three clients on one era, MaruEdit ships that era
  alone and adds the second only when a real client needs it.

The two adapters differ in what they may remember, and getting this wrong fails
conformance:

- **Legacy adapter.** Capabilities are negotiated once in `initialize` and are
  legitimately connection-scoped.
- **Modern adapter.** Protocol version and client capabilities arrive in
  `_meta` on *every* request and must be read from the request being served.
  Inheriting them from an earlier request is not an optimization, it is a
  conformance bug. `clientInfo` is only SHOULD, so a request without it is
  conforming and must be served — the indicator shows "unidentified MCP client"
  rather than refusing; malformed identity is rejected, absent identity is not.
  Either way it is self-reported display material, never an authorization input
  (§4.3). The adapter stamps `io.modelcontextprotocol/serverInfo` on every
  result.

This also corrects a claim in the first draft of this ADR: the bridge is **not**
stateless. It holds per-connection state — the selected era, in-flight request
ids, transport authorization, and rate-limit accounting. It does **not** hold
anchors: MaruEdit mints, validates, and evicts them, keyed by the app-issued
connection identity, and the bridge relays opaque handles only. Anything else
would put quota enforcement and disconnect cleanup on the side of the boundary
that cannot see the document. What it holds no state of is *business* state —
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
  connection raises a request the human answers **in a non-modal surface** — the
  connected-client indicator gains a pending entry, and opening it shows the
  executable path, pid, and any client-supplied name as *display only*, clearly
  labelled as unverified. It is deliberately not a sheet: an AppKit sheet is
  window-modal and would stop the human editing in that window, which R9 forbids
  and which would let a background agent's connection attempt interrupt someone
  mid-sentence. Unapproved connections are rate-limited so that a loop cannot
  flood the indicator.
- **Approval never blocks a call** (R17). The private `control.hello` returns
  `authorization.pending` immediately, and every MCP tool call from an
  unapproved connection returns a retryable tool error naming that state and how
  long to wait. Modern MCP has no handshake in which to park an indefinite wait —
  every request is self-describing — so a bridge that held the first request
  until a human clicked would look like a hung server. Dismissing the sheet is a
  denial: the connection is told `authorization.denied` and closed. A client that
  disconnects while the sheet is open cancels it, and reconnecting starts a fresh
  approval rather than resuming the old one.
- **Pairing is required before Phase 1 discloses anything**, not deferred to a
  later phase. Approving an anonymous connection cannot distinguish the intended
  agent from any other same-user process that read the token file and ran the
  same bridge, and "approve whoever asked at the moment you happened to click"
  is not an authorization decision. The flow is a one-time setup step per agent
  configuration:

  1. The human runs `maruedit-mcp --pair`. The bridge asks MaruEdit to start a
     pairing, and MaruEdit shows a short verification code in its indicator.
  2. The human confirms the same code in the terminal. On match, MaruEdit issues
     a credential for that configuration and writes it to a `0600` file.
  3. The agent's MCP server config points at that file — `--credential <path>` —
     rather than carrying the secret itself, because config files get committed
     and `argv` is world-readable.

  Every later connection presents the credential, and grants are keyed to it.

  **Be precise about what this buys.** The credential is a *revocable bearer
  capability*, not proof of identity. Any unsandboxed process running as this
  user can read the credential file just as it can read the session token, so
  possession does not prove which agent launched the shared bridge. What pairing
  adds is provenance at issuance — a human deliberately introduced this
  configuration, once, with a code they saw in both places — plus an
  individually revocable handle to attribute and cut off. Claiming a `0600` file
  solves same-user client identity would contradict P9 and ADR-011 §9.2, and it
  does not. That is why human approval still gates first use, why grants stay
  connection-scoped in Phase 1, and why unattended persistent grants (Phase 5)
  need a real isolation boundary — a signed helper with a Keychain ACL bound to
  its code signature, or user-presence-bound keys — rather than a longer-lived
  secret in a file.

---

## 5. Tool catalog

Tool names are short because they are re-sent in every prompt (P8). Clients
namespace them by server, so `read_document` reads as `maruedit / read_document`
at the call site.

Every tool declares an `outputSchema` and returns `structuredContent`. Every
recoverable failure is a tool execution error (`isError: true`) whose text names
the cause *and* the state needed to retry, never a bare JSON-RPC error (P5).

This section names each tool's arguments, results, and semantics; it does not
inline their JSON Schemas, and it should not — a schema that lives in prose
drifts from the one that ships. **Phase 1 owns a single versioned schema source**
from which the bridge catalog, the Swift DTOs, request validation, and the
conformance transcripts are all generated, so the two sides cannot disagree.
That source is where required-versus-optional fields, defaults, per-field size
caps, pagination and overflow behavior, the structured error shapes, the
per-phase schema differences, and the modern era's `ttlMs` and `cacheScope`
values are settled. Until it exists, no tool ships — including in Phase 1.

The catalog is defined against an **era-neutral internal outcome model** —
`success`, `toolFailure`, `inputRequired`, `cancelled`, plus list-cache and
subscription metadata — and each supported MCP era gets an explicit mapping
table in the bridge, tested by transcript:

| Internal outcome | 2026-07-28 | 2025-06-18 |
|---|---|---|
| success | `resultType: "complete"` + `content` + `structuredContent` | same result body, no `resultType` |
| tool failure | `resultType: "complete"` **and** `isError: true` | `isError: true` |
| input required | `resultType: "input_required"` + `inputRequests`, resumed by a retry carrying `inputResponses` and `requestState` | the legacy era does have server-initiated `elicitation/create`; MaruEdit **chooses** not to use it and returns a tool failure naming what to supply, because R17 forbids a tool call that waits on a human — a design decision, not a protocol limitation |
| cancellation (client → server) | `notifications/cancelled` for the request id | `notifications/cancelled` for the request id |
| cancellation (server behavior) | abandon the in-flight call; ADR-011 §8.5's rules on what is and is not revocable apply unchanged | same |
| tool list invalidation | `notifications/tools/list_changed`, delivered on a `subscriptions/listen` stream the client opened with `toolsListChanged` | `notifications/tools/list_changed` on the connection |
| document content change | `notifications/resources/updated` for the document's resource URI (§5.5), delivered on a `subscriptions/listen` stream opened with `resourceSubscriptions` | `resources/subscribe` on that URI, then `notifications/resources/updated` |
| list caching | `ttlMs` / `cacheScope` on every list result | omitted |

Two mistakes are easy to make here and both were made in an earlier draft of
this document. A modern-era tool failure carries `resultType: "complete"` *and*
`isError: true` — `resultType` is mandatory on every result, and a failed tool
call is still a complete result. And a *list*-changed notification is not a
*content*-changed notification: document changes ride
`notifications/resources/updated` in both eras, and only the mechanism for
establishing the notification stream differs.

### 5.0 Coordinate and text conventions (normative)

These exist because the codebase currently uses both conventions —
`LineIndex` is zero-based, `GrepService` output is one-based — and an
unstated choice here is an off-by-one in every client.

- **Text on the wire is LF-only Unicode.** A payload containing `\r` is rejected
  with `text.carriage_return`. Documents report their `lineEnding` as metadata.
  Read responses are never re-normalized — that would break the offsets and
  digests returned with them — so this holds only once Phase 0 has made LF a
  model invariant at every ingress (§3).
- **Edit addressing is by anchor or by offset.** Offsets are zero-based UTF-16
  code-unit indices into the LF-normalized buffer, half-open `[start, end)`.
  Edits never use line/column, which removes an entire class of off-by-one.
- **Human-facing positions are one-based lines** and one-based UTF-16 columns.
  They appear in `read_document` ranges, search results, outlines, and `reveal`,
  always alongside the corresponding offset.
- **Digests** are SHA-256 over the UTF-8 encoding of the LF-normalized region
  text, printed as `sha256:` plus lowercase hex.
- **Line ranges are half-open**: `startLine` is included, `endLine` is not, both
  one-based. A range's text includes the LF that terminates each included line
  except at end of file, where the buffer may not have one; `endLine` past the
  last line is clamped and the response reports what it actually returned.
- **Truncation is byte-bounded and boundary-safe.** `maxBytes` counts UTF-8
  bytes and truncation moves back to the nearest grapheme-cluster boundary, never
  splitting a code point or a combining sequence. A truncated response reports
  `truncated: true` and the offsets and line numbers it actually covers, not the
  ones that were asked for. `get_selection` bounds selected text the same way,
  with the same flag.
- **One address per edit.** An edit carrying both `anchorId` and `start`/`end`
  is rejected with `edit.ambiguous_address` rather than silently preferring
  one.

### 5.1 Orientation

**`list_documents`** — annotations: read-only.

```jsonc
// ← structuredContent
{
  "documents": [
    { "documentId": "doc_7f3a", "displayName": "notes.txt",
      "path": "/Users/x/notes.txt",
      "bufferState": "dirty", "backingFileState": "unchanged",
      "observedAt": "2026-08-22T09:15:04Z",
      "revision": 412, "metadataRevision": 7,
      "lines": 1840, "utf16Length": 96431,
      "encoding": "Shift_JIS", "lineEnding": "CRLF", "bom": false,
      "editable": true, "savableInPlace": true, "saveAsRequired": false,
      "editorIds": ["ed_1a", "ed_1b"] }
  ]
}
```

Buffer state and backing-file state are **independent fields**, because they are
independent facts: a document can be dirty *and* externally modified at once, and
a single collapsed enum forces an implementer to invent a precedence rule.

- `bufferState`: `clean` | `dirty`
- `backingFileState`: `unchanged` | `modified` | `missing` | `unknown`
- `observedAt`: when `backingFileState` was determined

`unknown` is not a hedge, it is the honest answer most of the time. The existing
detector is revalidation-only — it runs on window focus and before save, and its
result is presented to the human immediately rather than stored — so the model
has no continuously accurate answer to hand back. `list_documents` performs a
fresh off-main revalidation for granted documents and stamps `observedAt`;
observing an external change must never update the saved disk baseline as a side
effect, or the next real save would compare against the wrong thing.

Together these are how an agent learns that reading the path with its own
filesystem tool would give it the wrong text (P2).

Note what is *not* here: a selection. Selection belongs to an editor pane, not
to a document — `MainWindowController` can hold a `secondaryEditorVC` whose
`EditorViewController` owns separate TextKit storage and an independent cursor.
A document displayed in two panes has two selections (R16).

**`list_editors`** — read-only. One entry per open editor pane:
`{ editorId, documentId, windowId, isActive, isPrimaryPane, selectionRevision }`.

**`get_outline`** — read-only. The existing `OutlineModel` structure: heading
text, level, one-based line. A 40-line map of a 40,000-line document.

**`search_documents`** — read-only. Search over one document or all open
documents, returning `{ documentId, line, column, offset, lineText,
contextBefore, contextAfter }`. This is the tool that prevents "read the whole
file to find one function" (P8, R11). It runs off the main actor with hard
bounds (§6.4).

Two scope restrictions are normative rather than incidental:

- **Phase 1 ships literal search only.** Regular-expression search is deferred
  to a phase that can enforce a bound on it; §6.4 explains why a wall-clock
  deadline around `NSRegularExpression` is not a bound at all.
- **Phase 1 ships open-buffer scope only.** The folder scope arrives in Phase 3,
  and until then the Phase 1 schema rejects it rather than accepting a parameter
  it silently ignores. Folder search is an explicitly authorized filesystem
  read, not an exception to R14 — see §5.4 and §8.

**Enumeration is scoped too.** `list_documents` returns only documents inside
the caller's grant, and `list_editors` returns an editor pane **only if its
document is granted**. A window-level grant authorizes window-level operations
and never implies access to the documents that window holds, now or later —
otherwise it quietly undoes §8.1(4)'s frozen document grant by leaking the
identity, activity, and association of every document the human opens there.
Documents outside the grant are omitted entirely, not returned redacted, and the
response does not disclose how many were hidden — a path and a display name are
exactly the kind of thing a document the human did not authorize should not be
leaking.

### 5.2 Reading

**`read_document`** — read-only.

```jsonc
// → { "documentId": "doc_7f3a", "startLine": 200, "endLine": 260,
//     "withAnchors": true, "maxBytes": 65536 }
// ← structuredContent
{
  "documentId": "doc_7f3a", "revision": 412, "metadataRevision": 7,
  "bufferState": "dirty", "encoding": "Shift_JIS", "lineEnding": "CRLF",
  "startLine": 200, "endLine": 260, "totalLines": 1840,
  "startOffset": 8123, "endOffset": 11004,
  "truncated": false,
  "text": "…LF-only…",
  "anchors": [ { "anchorId": "a_9c21", "revision": 412,
                 "start": 8123, "end": 11004,
                 "startLine": 200, "endLine": 260,
                 "digest": "sha256:8f2c…" } ]
}
```

**Anchor minting is bounded and explicit, and arrives in Phase 2.** Phase 1's
`read_document` schema has no anchor fields at all — nothing can consume an
anchor before `apply_edits` exists, and shipping dead parameters invites clients
to depend on them.

From Phase 2 the two request fields are **mutually exclusive**:

- `withAnchors: true` mints exactly one anchor covering the returned range.
- `anchorRanges: [{ start, end }, …]` mints one anchor per entry. Offsets are
  document-relative, not response-relative, must lie inside the returned range,
  must not overlap, and are capped at **32 per call**.

MaruEdit never mints an anchor per line on its own initiative. Anchors are owned
by the **connection**, not by a "client" — Phase 1 has no persistent client
identity to hang them on (§4.3), and a self-declared agent name would make the
quota spoofable. Each connection holds at most **256 live anchors**; minting
past that evicts the oldest. An anchor is invalidated by any text revision
change, by document close, and by the connection ending, so an anchor set cannot
outlive the snapshot that gave it meaning and repeated reconnects cannot
accumulate orphaned quota. No separate expiry timer is needed.

Text is always the buffer, never disk (R1, R2), and always LF (R12). `revision`
and `metadataRevision` are mandatory in the response because they are the
preconditions for every text edit, proposal acceptance, and save (R3). Selection
writes take `selectionRevision` instead and do not carry a metadata
precondition. Omitting the line range reads the whole
document, subject to `maxBytes` and an explicit `truncated` flag — a truncated
read is never silently truncated (P5).

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
  "baseMetadataRevision": 7,
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

- **Strict snapshot.** `baseRevision` must *equal* the document's current text
  revision, and `baseMetadataRevision` its current metadata revision. There is
  no "apply anyway if the anchors still match" path in v1; §6.2 explains why,
  and OQ-2 holds the door open for tracked anchors later. The metadata
  precondition is not decoration: a human can change an untitled document's
  encoding, its BOM, or its line-ending style without touching a character of
  text, and an edit validated as representable in UTF-8 is not necessarily
  representable in the Shift_JIS the document has since become.
- **Anchors are snapshot handles, not tracked ranges.** An anchor is valid only
  at the revision that minted it. Its value over a raw offset is that the agent
  proves it is editing the region it read by echoing a 32-byte digest instead of
  a paragraph of text (P8).
- **Atomic, and atomic about more than text.** Edits are validated as a set —
  bounds, overlap, digests, encoding representability — and then applied in one
  transaction. Any failure fails the entire call and mutates nothing (R6).
  Overlapping edits are rejected, not merged.

  "Nothing" has to include the editor's offset-based state. A document carries
  bookmarks, color markers, edit marks, folds, the line index, selections, and
  highlight ranges, all addressed by offsets that an edit invalidates. Today
  these are handled unevenly: `batchReplace` transforms some of them, its undo
  snapshot restores bookmarks and color markers but not edit marks, and ordinary
  typing normalizes several sets after the fact. The transaction primitive must
  state, for every one of those sets, whether an edit transforms it or
  invalidates it, and its undo must restore exactly what it changed. The
  atomicity test compares that state too, not just text and undo depth —
  otherwise a "failed" batch can leave a document whose text is intact and whose
  bookmarks are not.
- **Teaching failures, without lying about what is knowable.** Three outcomes
  are distinguishable, and when more than one precondition fails they are
  reported in this precedence order:
  1. `state.text_revision_conflict` — the text moved. Because anchors are not
     tracked, MaruEdit does **not** know where the old regions went or whether
     they still exist, so the error carries only the new text and metadata
     revisions, the line count, and the length, and says plainly that the agent
     must re-read or search. It must never present text found at the old numeric
     offsets as though it were the same region; that is the fuzzy-match failure
     of §1.1 in a new costume.
  2. `state.metadata_conflict` — the text revision matches but the metadata
     revision does not, so the offsets are still valid while the assumptions
     underneath them are not. The error carries the current metadata and the
     unchanged text revision; the agent re-runs whatever depended on it —
     encoding representability, above all — and resubmits the same offsets
     against the new `baseMetadataRevision`. Forcing a full re-read here would
     be a lie in the other direction.
  3. `state.digest_mismatch` — both revisions match, so the offsets are exactly
     meaningful. The error carries the current text at each failed range and a
     fresh anchor for it, and the agent can retry immediately (P5).
- **One undo entry**, named `"claude-code: fix typo in section 3"` (R7). ⌘Z is
  the universal reject button. The name shown is the *claimed* client name, and
  §4.3 says that is unverified, so the UI marks it as claimed and the audit log
  records the trusted pairing and connection identity alongside it — an
  attribution nobody can spoof by naming themselves after someone else. Labels
  are sanitized for display: single line, bounded length, no control or
  bidirectional characters. The raw value survives only in structured audit
  fields. This requires a new transaction primitive; the
  existing `batchReplace` silently drops out-of-bounds ranges, merges overlaps,
  and hard-codes its undo action name, so it cannot back this contract (§9,
  Phase 0).

  It also requires deciding who *owns* that undo entry. Split panes hold
  separate `NSTextStorage` instances and undo is registered on the initiating
  text view, so a document shown in two panes has two undo histories and ⌘Z
  after an agent edit would depend on which pane has focus. Phase 2 resolves
  this one of two ways, and must pick before it ships: route undo and redo for
  every pane showing a document through one coordinated per-document history,
  or — if that proves too invasive for the current architecture — **refuse agent
  writes to a document displayed in more than one pane**, with a structured
  `document.multiple_panes` error. Shipping "one ⌘Z" while it silently means
  "one ⌘Z in whichever pane you were last in" is the worse option than refusing.
- **Encoding is enforced at edit time.** If inserted text contains characters
  not representable in the document's encoding, the call fails with
  `encoding.unrepresentable` listing the offending scalars, rather than
  producing a document that cannot be saved without a human conversion decision.
- **`mode`** is `apply` or `review`, bounded by the client's grant. `review`
  returns immediately with `{ "status": "pending", "proposalId": "prp_2b" }` and
  never blocks the tool call while a human decides (R17).
- **`idempotencyKey`** is optional but recommended: a repeated call with the
  same key returns the original outcome instead of creating a second proposal or
  a second edit. The record is keyed by *(connection, tool name, key)* and
  stores a canonical digest of the arguments. Reusing a key with different
  arguments is refused with `idempotency.mismatch` rather than silently
  returning someone else's result. Conflict outcomes are cached alongside
  successes, so a blind retry after a conflict returns the same conflict instead
  of re-running the validation. Records are bounded — 64 per connection, evicted
  oldest-first, and dropped after 10 minutes — and, because Phase 1 has no
  persistent identity (§4.3), **deduplication does not survive a reconnect**. An
  agent that loses a response and reconnects must re-read and decide for itself,
  which is safe precisely because writes are revision-gated.

**`review_status`** — read-only. `{ proposalId }` → `pending` / `applied` /
`rejected` / `conflicted` / `expired`, with the resulting revision when applied.

**`set_selection`** / **`reveal`** — `{ editorId, baseSelectionRevision, … }`.
Move the human's cursor and scroll to a line. Small tools with outsized value:
"here is what I changed" is a selection, not a paragraph of prose. The selection
revision precondition exists so an agent cannot yank a cursor the human just
moved (R9, R16).

**`save_document`** — `{ documentId, expectRevision, expectMetadataRevision }`,
split into preflight and commit because the existing save path can present modal
alerts for external modification, mixed line endings, and unrepresentable text,
and a modal inside a tool call would violate R17 and can hang an MCP request
indefinitely. Preflight returns a structured outcome — `ok`, `external_change`,
`mixed_line_endings`, `unrepresentable`, `save_as_required`, `read_only` — and
only `ok` proceeds to a commit. Anything else is reported to the agent and, where
a human decision is genuinely required, surfaced in MaruEdit as a pending item
the human resolves on their own time. The commit protocol itself is §6.5, and it
is the one place in this design where getting the ordering wrong silently marks
unsaved work as saved.

**`open_document`** — `{ path, windowId }`, capability-gated, and Phase 3 at the
earliest, because an arbitrary path plus a frozen grant is a contradiction: read
it one way and `documents.open` becomes broad filesystem-read authority, read it
the other and the opened document is invisible to its own caller. The normative
policy:

- The path must resolve inside a directory root the human authorized for this
  connection — the same roots that gate folder search. Without such a root, the
  tool is unavailable rather than permissive.
- **Canonicalizing a URL is not the security boundary.** A path component can be
  replaced between the check and the open, so containment must be enforced by
  descriptor-relative traversal from an opened root descriptor, refusing
  symlinks at every component with `O_NOFOLLOW`, and verifying the final file's
  identity and type before use. String comparison after `resolvingSymlinksInPath`
  passes a review and loses a race.
- **The verified descriptor is the authority, not the path.** Today's lifecycle
  reopens a URL by path, and folder search enumerates and reads by path
  throughout, so verifying a path and then reopening it hands the race straight
  back. Phase 3 therefore owes an fd-based loader — size check, decode, identity
  capture, and document construction from the already-open descriptor — and
  descriptor-relative enumeration for folder search. Until that exists,
  `open_document` and folder scope do not ship.
- Opening otherwise routes through the normal document lifecycle, so encoding
  detection, profile resolution, and large-file mode behave exactly as they do
  for a human.
- A successfully opened document joins the caller's grant, for that document
  only. This is the one sanctioned way a frozen grant grows, and it grows by an
  object the human's own authorization already covered by root.

**`run_command`** — `{ commandId, windowId, editorId | documentId }`,
default-deny. A command is reachable only if its registry definition is
explicitly marked agent-exposed and the client holds `commands.run`. Registering
a command must never make it remotely invocable (unchanged from ADR-011 §9.7).
Commands that can present modal UI are not eligible (R17).

**The target is required, and today it cannot be honoured.** `CommandContext`
currently carries only the coordinator, so a command runs against whatever
window happens to be key — meaning a human switching tabs between authorization
and execution could redirect an agent's command to another document, and an
object-scoped grant could not be enforced for a command whose target is unknown.
ADR-011 §12.6 already identified this as a real refactor rather than a detail.
Phase 3 therefore either lands explicit targets in `CommandContext` and resolves
exposed commands exclusively through them, or exposes only commands proven to be
process-global and document-independent. Stealing focus to manufacture a target
is not an option.

### 5.3.1 Documents this profile will not write

"Writable" is three different questions, and MaruEdit already answers them
separately: editing is disabled only by read-only or view mode, while overwrite
protection is checked at save time and leaves the buffer perfectly editable.
`list_documents` therefore reports three predicates, not one flag —
`editable`, `savableInPlace`, and `saveAsRequired` — and the write tools consult
the one that applies: `apply_edits` needs `editable`, `save_document` needs
`savableInPlace` and otherwise returns `overwrite_prohibited` or
`save_as_required`.

The states that make a document non-editable, rejected before any other
validation:

- **Binary mode**, reported as `contentKind: "hex"` on both `list_documents`
  and `read_document`, with `encoding` and `lineEnding` reported as inapplicable,
  so an agent cannot mistake a hex rendering for the file's text. Text documents
  report `contentKind: "text"`. A binary document's buffer holds a hex
  *rendering*, and
  saving parses that rendering back through `BinaryDocumentCodec` rather than
  the policy → line-ending → encoding pipeline that §6.5 describes. An agent
  editing hex text through a text API is a corruption engine, so binary
  documents are excluded from `apply_edits` and `save_document` in v1 and are
  readable only.
- **View mode** and **read-only**, which already disable editing in the app.

**Overwrite-prohibited** is different: it does not block editing, only saving in
place, exactly as it does for the human, who can still edit and then Save As.

Excluding them is cheap; discovering them at commit time is not.

**Writability must be an effective predicate, not a single flag, and it must
reach every pane.** Read-only has three independent sources today — filesystem
permissions, large-file read-only mode, and the file-type profile's
`opensReadOnly` load policy — and only `Document.open` consults all three.
`refreshReadOnlyState()`, which runs every time the window becomes key,
recomputes from permissions and large-file mode alone, so a profile-read-only
document whose file is writable on disk silently becomes writable again on
focus. Worse, split creation sets the secondary editor editable unconditionally,
so a read-only or view-mode document is editable today in its second pane
regardless of any of the three sources. That is a bug in the app today; this profile
cannot inherit it, because `list_documents` would then advertise the document as
writable and admit agent edits into a document the profile said to protect.
Phase 0 introduces one effective-writability predicate that preserves every
source, applies it to every pane including one created later by a split, and
tests each source being set and cleared independently in both panes.

### 5.4 Deliberately absent

No `read_file`, `write_file`, `list_directory`, `run_shell`,
`run_external_command`, or network tool. Every agent that will connect already
has better versions of those. What no agent has is a correct view of an unsaved
Shift_JIS buffer that a human is typing into — that, and only that, is what
MaruEdit should sell (R14).

One honest exception, and not before Phase 3: `search_documents` with a folder
scope *is* a filesystem read primitive. It is bounded rather than general — an explicitly authorized
root, entered through a descriptor-relative traversal that refuses symlinked
components rather than a canonicalized string comparison (§5.3), with a hard cap
on matches and bytes returned — and it is described that way in the approval
surface rather than hidden behind the phrase "search".

`external.*` commands stay unreachable in v1. The reason is not that agents
already have shell access — a sandboxed or remote agent may not — but that
MaruEdit's curated external commands run with full user authority, and routing
them through an automation grant makes the audit trail ambiguous about which
process caused a subprocess to run. They are deferred and intentionally
unsupported by this profile, not judged capability-equivalent.

### 5.5 Resources

Resource notifications need something to name. Phases 1 through 3 expose no MCP
resources at all — the tools are self-sufficient and a second way to read the
same text is a second thing to keep consistent. Phase 4, which introduces change
notification, adds exactly enough to make subscription meaningful:

- A document's resource URI is `maruedit://document/<documentId>` — opaque,
  process-lifetime-scoped like every other handle, and returned by
  `list_documents` so a client never has to construct one.
- `resources/list` enumerates the caller's granted documents, and
  `resources/read` returns the same authoritative buffer text `read_document`
  would, with the same revisions in `_meta`.
- An update notification carries only the URI. It is an invalidation hint, not a
  payload: the client re-reads to get text and revision together, which is the
  only way it can be sure the two agree.

Without this, the notification rows in §5's table name a URI that does not
exist, and no client could subscribe to anything.

---

## 6. Concurrency model

One authority, optimistic concurrency, no locks.

### 6.1 Revisions

Three independent monotonic counters, because they answer different questions
and conflating them makes every precondition either too strict or useless:

- `revision` — document text. Incremented by any text mutation from any source.
- `selectionRevision` — per editor pane. Incremented by cursor and selection
  changes.
- `metadataRevision` — everything else about the document that can change what
  an edit is allowed to contain or how a save serializes it.

`metadataRevision`'s domain is enumerated rather than described, because "the
metadata" is exactly the kind of phrase two engineers read differently:
encoding, BOM presence, line-ending style, file identity and modification date,
target URL, POSIX permissions, read-only state, view-mode state,
overwrite-prohibited state, binary-mode state, the resolved file-type profile,
and that profile's save policy. The last one matters more than it looks — a
profile change can replace the save policy, which rewrites text on the way to
disk, without touching any field named earlier in that list. The three state
flags matter because they decide whether an operation is admissible at all.

| Event | `revision` | `selectionRevision` | `metadataRevision` |
|---|---|---|---|
| Text mutation from any source | ✓ | ✓ if selections moved | — |
| Selection or cursor change | — | ✓ | — |
| Assignment that changes nothing | — | — | — |
| Encoding / BOM / line-ending change | — | — | ✓ |
| Profile or save-policy change | — | — | ✓ |
| Save As to a new URL | — | — | ✓ |
| Successful save | — | — | ✓ (identity and modification date) |
| Reload from disk | ✓ | ✓ | ✓ |
| Undo / redo | ✓ | ✓ | ✓ if it restores metadata |

A no-op assignment increments nothing: revisions exist to answer "did the thing
I read change", and a counter that ticks on identical values makes every
precondition spuriously fail.

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
   **both** revision preconditions — text and metadata — and every validation
   whose result depends on metadata, encoding representability above all.

The same re-validation runs when a human accepts a pending proposal, because the
grant may have been revoked, or the document's encoding changed, while the
proposal sat in the queue.

### 6.4 Where work runs

`@MainActor` is for target resolution, snapshot capture, and mutation. Nothing
else. Outline construction, search, digest computation, encoding-representability
checks, truncation, and JSON serialization run off the main actor against an
immutable snapshot tagged with the revisions it was taken at. In-memory search
can scan up to ten million characters per document today, so running it on the
main actor would visibly stall typing and break R9.

The snapshots and results that cross that boundary must be `Sendable` value
types defined for the purpose. `Document` is a mutable class marked
`@unchecked Sendable` that owns an `NSTextStorage`, so nothing stops an
implementation from capturing it in an off-main task except a rule and a
strict-concurrency build setting; Phase 0 establishes both.

Every read tool carries explicit bounds — document bytes, pattern length, match
count, context bytes — and returns a structured `limit.*` error rather than
running long.

**A deadline is not a bound on a call that cannot be interrupted.** The existing
engine makes one synchronous `NSRegularExpression.matches` call with no
cancellation point, so a catastrophically backtracking pattern cannot be stopped
by any timer this process owns: moving it off the main actor protects typing but
still burns a core until it finishes, and a client that repeats the request has
a denial-of-service primitive. Phase 1 therefore ships **literal search only**.
Regular-expression search returns when one of these exists, in preference order:
a regex engine with enforceable resource limits, execution in a killable helper
process, or a tested conservative rejection policy for unbounded-backtracking
patterns (OQ-8). Until then the ADR promises no regex deadline, because it could
not keep one.

### 6.5 Saving

Saving is the one operation that touches the filesystem, and it is where an
ordering mistake marks unsaved work as saved. The existing path calls
`Document.save()` synchronously on the main actor and then `markSaved()`, which
records the document's *current* content as the saved baseline — correct when
nothing can change in between, wrong the moment encoding and I/O move off-main.

Three values must be named separately, because conflating them is how the
current code arrives at its bug:

- **`sourceSnapshot`** — the buffer text as captured, in LF form.
- **`serializedBytes`** — what actually reaches disk: `sourceSnapshot` after the
  file-type profile's save policy has transformed it (trailing-whitespace trim,
  final-newline insertion), after line-ending application, and after encoding.
  These differ whenever the resolved profile configures a transforming save
  policy: a buffer holding `"new  "` is written as `"new\n"` under a profile
  that trims trailing whitespace and ensures a final newline. Neither option is
  on by default and no built-in profile installs a save policy, so with the
  stock configuration the two values coincide — which is exactly why an
  implementation that conflates them passes its first tests and fails later.
- **`diskBaseline`** — file identity, modification date, and POSIX permissions
  as observed at plan time.

**One coordinator owns saving, or none of this holds.** The protocol below is
worthless if only `save_document` follows it: today `Document.save()` mutates
file state and calls `markSaved()` synchronously, and Save, Save As, and
save-on-close each invoke it independently. A per-document `SaveCoordinator`
becomes the sole filesystem-save authority, and every entry point — human Save,
Save As, save-on-close, agent save, and any future autosave — goes through the
same plan → prepare → fence → commit → finalize machine. Phase 2 does that
migration *before* enabling agent saves, because a fence only one participant
respects is not a fence.

The commit protocol is normative:

1. **Plan, on the main actor.** Capture an immutable `SavePlan`: text revision,
   metadata revision, `sourceSnapshot`, encoding, BOM, line-ending style,
   resolved profile and save policy, target URL, POSIX permissions, and
   `diskBaseline`.
2. **Prepare, off the main actor.** Policy transformation, line-ending
   application, encoding, and representability checking run against the plan,
   never against the live document, producing `serializedBytes`.
3. **Revalidate and fence, on the main actor.** Both revisions and
   `diskBaseline` must still match. If either moved, the save fails with the
   matching conflict from §5.3 and nothing is written. This is the last
   cancellation point. In the same transaction, reserve a **per-document save
   generation**. Releasing the main actor for step 4 is what makes this fence
   necessary; today's synchronous save avoids the race only by never yielding.

   The fence is deliberately asymmetric, because P1 is:

   - **Another agent's save** of the same document is refused with
     `save.in_progress`. A queue there would hide the ordering question rather
     than answer it.
   - **The human's ⌘S or Save As** always wins. Before the irreversible point it
     supersedes the agent save, which is abandoned and reported as
     `state.superseded`. After the irreversible point it cannot cancel a write
     already in flight, so it is recorded as pending human intent and runs
     automatically the moment finalization completes, against fresh state. It is
     never refused and never silently dropped — a human pressing ⌘S and getting
     an error because a background agent was mid-save is exactly the failure P1
     exists to prevent.
   - **Typing** is never affected at all.
4. **Commit, off the main actor.** Backup creation and rotation run first — they
   copy the previous file and may delete an older backup, so the irreversible
   point begins *there*, not at the destination write — followed by the existing
   atomic write.
5. **Finalize, on the main actor, in one transaction.** Verify the save
   generation is still the one this commit reserved and that the target URL has
   not changed — a Save As that slipped through would otherwise let a stale
   finalizer stamp identity from the wrong file. Then record `sourceSnapshot`
   as the saved baseline, refresh file identity, modification date, and
   permissions from what was written, bump `metadataRevision`, and recompute
   dirty state by comparing the live buffer against `sourceSnapshot`. If the
   human typed during step 4, that comparison leaves the document **dirty**,
   which is correct: the newer text is genuinely unsaved. Today's `markSaved()`
   copies whatever `content` holds at completion and would claim the opposite.

   Text is not the only thing that can change during step 4. The human can also
   switch encoding, BOM, line ending, or file-type profile, and the document
   tracks that separately as format dirtiness (`isFormatModified`). Finalization
   must therefore keep the *live* metadata, record the plan's serialization
   settings as what the file on disk actually reflects, and leave the document
   **format-dirty** whenever a serialization-affecting value changed after
   step 3. Clearing format dirtiness unconditionally — which today's
   `markSaved()` also does — would report a document as saved in a form it was
   never saved in.

The saved baseline is `sourceSnapshot` rather than `serializedBytes` on purpose:
it preserves the existing clean-state semantics, under which a document whose
save policy rewrote its text on the way out is still considered saved. A digest
of `serializedBytes` is retained alongside `diskBaseline` for external-change
detection.

**Every path out of the machine is named, because the failure paths are where a
fence leaks.** The coordinator has five terminal states, and each releases the
fence exactly once, settles any pending human intent, and produces one stable
tool result and one audit record:

| Terminal state | When | Document left as |
|---|---|---|
| `succeeded` | finalization completed | clean against `sourceSnapshot`, or dirty/format-dirty per step 5 |
| `failed_before_irreversible` | revalidation, encoding, or plan failure | untouched; disk untouched |
| `failed_after_irreversible` | backup or write failed once the commit began | dirty; disk state reported as `unknown` until the next observation, and the backup left in place rather than cleaned up behind the human's back |
| `superseded` | a human save won before the irreversible point | untouched; the human save proceeds |
| `abandoned_on_shutdown` | the app terminated mid-commit | recovery data preserved; the next launch reports an unfinished save rather than assuming either outcome |

A pending human save runs after any terminal state, against fresh state, never
silently dropped. The coordinator outlives document and window close while a
filesystem operation is in flight — closing a document during commit detaches
the UI but not the machine, and its finalizer must tolerate the document being
gone by writing the audit record and releasing the fence without touching model
state.

**One honest limitation.** Revalidating file identity and then writing leaves a
TOCTOU window: `ExternalChangeDetector.check` is an observation, and the atomic
replacement that follows is not a compare-and-swap. External-change protection
here is best-effort revalidation, materially better than no check and not a
guarantee. Closing it properly needs a conditional-replacement mechanism, which
is out of scope for this ADR.

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
baseMetadataRevision, perEditDigests, normalizedEdits, client, label, createdAt }`.
It is never rewritten, relocated, or merged.

On acceptance, the same atomic check that guards a direct write runs again —
both revisions, every digest, and encoding representability against the
encoding the document has *now*. If either revision moved while the proposal was
pending — the human kept typing, or changed the encoding, both of which they are
explicitly allowed to do (P1) — the proposal becomes `conflicted`, nothing is
applied, and the agent must re-propose against the new state. Silently applying stored ranges to a document that has moved is the
exact lost-update bug this whole design exists to prevent.

**Retained state needs its own budget, because request-rate limiting does not
bound it.** A proposal holds all of its edit text, and the inherited transport
allows 16 MiB frames and dozens of in-flight requests, so an authorized but
buggy agent could otherwise pin hundreds of megabytes of proposal text inside
the editor without ever exceeding a rate limit. Before Phase 2 ships:

| Bound | Value |
|---|---|
| Edit bytes per `apply_edits` call | 1 MiB |
| Pending proposals per connection | 8 |
| Pending proposals per document | 4 |
| Proposal bytes per connection | 4 MiB |
| Proposal bytes per process | 32 MiB |
| Proposal lifetime | 10 minutes |
| Label length | 200 characters |
| Idempotency key length | 128 characters |

Exceeding a count or byte bound is a structured `limit.pending_proposals` or
`limit.proposal_bytes` failure, and rate limiting is byte-weighted rather than
request-counted so a few enormous calls cost what they actually cost. Proposals
also expire on document close and are dropped on revocation. The 10-minute
lifetime settles OQ-5: expiry is not announced, because a notification channel
does not exist before Phase 4 and an agent that cares learns it from its next
`review_status` poll.

### 7.2 Required surfaces

- A status-bar indicator naming every connected client, with a one-click
  disconnect. If a user cannot tell an agent is attached, the feature is not
  shippable.
- A review banner with a real diff, per pending proposal, keyboard-operable, and
  showing the proposal's base revision so a conflicted proposal is legible.
- A session log — timestamp, pairing and connection identity, claimed client
  name marked as claimed, tool, document, revisions, outcome — visible in the
  app, not only in a file (R15).
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
2a. **One endpoint per instance.** ADR-011 assumes a single `endpoint.json` and
   `control.sock`, and reclaims a stale one after checking ownership and object
   type. MaruEdit has no single-instance lock — `main.swift` starts the event
   loop directly — so a second instance can overwrite the first's discovery file
   or unlink a live socket. Endpoints are therefore per instance, in a directory
   keyed by pid and process start time, listed through a lock-protected registry
   file that discovery reads. Reclaiming an entry requires the recorded start
   time to match a dead pid, or a probe of the existing listener to fail;
   ownership and socket type alone are not enough. **Discovery fails closed when
   more than one instance is live**: the bridge refuses rather than guessing
   newest, first, or frontmost, and the human disambiguates with
   `--instance <serverInstanceID>`. Pairing takes the same argument, and the
   credential it issues is bound to the installation it was issued by, so a
   second instance cannot inherit it. Selecting by pid alone is never
   acceptable — pids are reused.
3. **Identity.** ADR-011 §9.4's "process names are not identities" is extended:
   because every agent launches the same bundled bridge, *no* property of the
   connecting process may key a grant. Phase 1 pairs each agent configuration
   (§4.3) and keys grants to that credential, but the credential is a bearer
   capability, so grants remain **connection-scoped** and human approval still
   gates first use. Phase 5 adds *persistent* grants that survive restarts, and
   that step — not pairing itself — is what needs the stronger isolation
   boundary.
4. **Grant scope.** ADR-011's capabilities were per-client only. This profile
   requires them to be object-scoped as well: a grant names the documents,
   window, or authorized directory roots it covers. A blanket `documents.read`
   over everything now and in the future is a different and much larger grant
   than it appears.

   **A grant freezes at approval.** It covers exactly the documents open when
   the human approved it. A document opened afterwards is not covered, is
   omitted from enumeration, and needs its own approval — because the alternative
   silently converts "you may read what I have open" into "you may read anything
   I open later", which is how an unrelated secret ends up in an agent's context
   because someone opened a file. That inheritance is available as a separate,
   conspicuously labelled *"include documents I open while this client is
   connected"* switch in the connected-client indicator, **default off**, and it
   lapses when the connection ends. Documents outside the grant are omitted from
   enumeration entirely (§5.1). OQ-3 covers whether a persistent grant may
   inherit more than that; it cannot be answered before OQ-1.
5. **Writer lease and External Commands** are removed from this profile (§6.2,
   §5.4).
6. **No modal UI** may be reached from any agent-initiated call (R17), which
   constrains both `save_document` and `run_command` exposure.
7. **Public wire protocol.** ADR-011 §7 lists "MCP server" among its explicit v1
   exclusions; this profile reverses that for the public surface, which is now
   MCP and nothing else. ADR-011's `control.hello` handshake, request/response
   envelopes, notification and cancellation frames, and two-dimensional version
   negotiation (§11) now describe **only the private bridge↔app channel**, where
   they remain normative and where `control.hello` is still the first frame on
   every connection. They no longer describe anything an agent sees.

   ADR-011's **method catalog (§6) is superseded outright**, on the private
   channel too. It has no representation for ranged reads, anchors, edit
   transactions, metadata preconditions, proposals, outline or search, structured
   save preflight, the fenced commit, or idempotency — that is, for most of what
   this profile does. Claiming it stayed normative while Phase 1 also specified a
   new internal protocol was a contradiction. The private channel carries a
   single versioned `agent.call` envelope wrapping a typed internal request and
   outcome, so the internal operation set tracks the tool catalog without a
   second protocol negotiation, and that envelope carries the connection
   identity, grant generation, cancellation token, and error mapping the tools
   depend on.
8. **Request ordering.** ADR-011 §8.2 requires strict per-connection FIFO
   processing. That is superseded. A modern client holds a
   `subscriptions/listen` request open for the life of its subscription, so
   FIFO would park every later request behind a call that returns only at
   teardown — a deadlock, not an ordering guarantee. A connection may have
   several requests in flight; subscription streams are exempt from execution
   ordering entirely; and consistency comes from where it actually comes from in
   this design: main-actor serialization of commits per document, revision
   preconditions, and the save fence. Where an agent needs read-after-write
   ordering it gets it by reading the revision it just wrote, not by trusting
   the transport.
9. **Actor boundary.** ADR-011 §8.1 places target resolution before main-actor
   dispatch. This profile puts target resolution *on* the main actor (§6.4),
   because resolving a `documentId` or `editorId` means reading live controller
   state; what moves off-main is everything after the snapshot is taken.
   ADR-011's rule that *permission* checks precede main-actor dispatch is
   unchanged and is strengthened by the second check in §6.3.

### 8.2 Capabilities

`documents.read`, `documents.write`, `documents.open`, `documents.save`,
`selection.read`, `selection.write`, `search.folder`, `commands.run` — each
scoped per §8.1(4), each revocable individually in Settings, each surfaced in
plain language when approval is requested.

Clipboard access is **not** in v1. Earlier drafts listed `clipboard.read` and
`clipboard.write` as capabilities and Phase 3 listed "clipboard" as a
deliverable, but neither ever acquired a tool name, schema, size bound, or error
model — and on inspection it earns none of that work. Every agent that will
connect already has its own clipboard story, reading the human's clipboard is a
pure exfiltration channel with no editing value, and writing it is
surprise-at-a-distance nobody asked for. Removed rather than specified.

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
`MacroCommandBridge`; keep `maru.*` observably identical except for the one
carve-out §3 decides: a macro that inserts CR now gets LF. Add process-lifetime
`documentId` / `editorId` / `windowId`. Add the three revision counters of §6.1
and the single mutation-notification boundary, auditing every existing path that
mutates `Document` — `textDidChange`, `batchReplace`, undo snapshot restore,
reload, encoding change, direct assignment. Run a **separate selection-boundary
audit**: programmatic `setSelections` deliberately bypasses the AppKit selection
callback that user edits arrive through, so a counter wired only to
`textViewDidChangeSelection` would miss every macro and agent selection change,
while a counter wired naively would also count the duplicate assignment
`batchReplace` makes after rehighlighting. The audit must also cover
`synchronizeSharedDocumentState()`, which clamps `textView.selectedRanges`
directly after replacing a pane's storage: it can move the visible selection
while leaving the `SelectionSet` that the macro bridge reads stale, so a
selection counter attached only to the documented paths would miss a real
change. One selection-mutation boundary updates `SelectionSet`, the AppKit
selection, and `selectionRevision` exactly once. Introduce the **pre-mutation
canonicalizer** of §3 and route every ingress in that table through it,
including the value-backed rewrite of Insert Control Code that §3 requires.
Introduce the **effective-writability predicate** of §5.3.1 so that read-only
stops depending on which code path last recomputed it. Build the
**validated transaction primitive** underneath both adapters: bounds and overlap
rejection before any mutation, one undo snapshot, caller-supplied undo label,
typed result, and a written contract for every offset-based set a document
carries — bookmarks, color markers, edit marks, folds, line index, selections,
highlight ranges — saying whether an edit transforms or invalidates each, with
undo restoring exactly what was changed. Keep the macro path's existing lenient overlap behavior by adapting
it, not by weakening the primitive. Define the `Sendable` snapshot and result
DTOs the off-main workers will use, forbid `Document`, controller, and AppKit
references in worker closures, and build the new targets under strict
concurrency checking — `Document` is `@unchecked Sendable` and owns an
`NSTextStorage`, so the compiler will not catch that mistake for us. No socket,
no bridge, no protocol.
*Exit:* macro tests pass unchanged apart from the documented CR carve-out;
Insert Control Code maps `SO`, `US`, and `DEL` to the same bytes as before the
rewrite and no longer offers CR; every read-only source survives a
window-focus refresh and in a pane created later by a split;
revision-source tests cover every text and selection mutation path and every row
of §6.1's event table; a CR inserted through every row of §3's ingress table is
normalized; the transaction primitive rejects a batch containing one invalid
range without mutating the document.

**Phase 1 — Read-only MCP.**
Measure which MCP revision each target client sends (§4.2) and record it here.
Add the SwiftPM executable target for the bridge, its universal build, bundle
placement, nested code signing, notarization verification, and a CI launch test.
Specify the bridge↔app internal protocol — request ids, cancellation, error
model, caller credential propagation, reconnect — with framing and fuzz tests,
and generate the bridge's static tool catalog from the same schema source as the
app so the two cannot drift. Implement the socket, token file, the per-instance
endpoint registry, the peer-credential check, the §4.3 pairing flow and `--pair`
mode, the non-modal approval surface, rate limiting, the connected-client
indicator, and the audit log. Ship `list_documents`, `list_editors`, `read_document`, `get_outline`,
`search_documents` (literal, open buffers only), and `get_selection`, all
executing off-main with bounds and all filtered to the caller's grant.
*Exit:* `claude mcp add maruedit -- …`, the equivalent Codex `config.toml` block,
and `openfox mcp add` each produce a working read-only integration with no
MaruEdit-specific client code; and with a full-document literal search running
against a 10 MB buffer, p99 **edit-handler** latency stays under **8 ms** and
within **10%** of the same measurement with no client connected.

The metric is named precisely because the existing signpost measures precisely
that: it opens in `textView(_:shouldChangeTextIn:replacementString:)` and closes
at the end of `textDidChange`, which covers model update, line-index
maintenance, and highlight scheduling but stops before AppKit layout and glyph
presentation. Calling it keystroke-to-glyph would be a claim the instrument
cannot support. `docs/performance.md` records no keystroke budget at all today,
so this ADR sets one; Phase 1 also has to add the harness that drives synthetic
keystrokes and collects the p99 interval under concurrent load, because no such
harness exists either.

**Phase 2 — Revision-gated writes.**
Bounded anchor minting per §5.2 and digest validation; `apply_edits` with strict
snapshot semantics on both revision counters, atomic application, the **three**
ordered conflict outcomes of §5.3, the non-writable document states of §5.3.1,
undo labelling, LF enforcement, and edit-time encoding representability checks;
`set_selection` and `reveal` with selection revisions; the `SaveCoordinator` migration that puts every
existing save entry point on one machine; `save_document` preflight plus the
§6.5 commit protocol, including the three-value split, the per-document
save fence, a `markSaved`-equivalent that records `sourceSnapshot` rather than
whatever the buffer holds when the write returns, and format-dirty preservation;
the split-pane undo decision of §5.3, taken and implemented before any write
ships; review mode, immutable proposals, and the diff banner.
*Exit:* an agent edits a dirty Shift_JIS CRLF document while a human types in
it, and neither loses work; a proposal accepted after the human typed is
reported `conflicted` rather than applied.

**Phase 3 — Scoped app control.**
Authorized directory roots and their containment checks first, since both
`open_document` and folder search depend on them; then `open_document` per §5.3,
`run_command` behind the default-deny allow-list with modal-free screening and
either explicit `CommandContext` targets or a document-independent-only command
set, and regular-expression search once §6.4's bounding problem has an
answer.
*Exit:* no registry command is reachable merely because it was registered; no
folder search and no `open_document` escapes its authorized root through a
symlink; an exposed command run with an explicit target does not follow window
focus when the human switches tabs mid-call.

**Phase 4 — Change awareness.**
The §5.5 resource surface — document URIs, `resources/list`, `resources/read` —
followed by coalesced document-change events carrying revisions, so a long-lived
agent can invalidate its cache instead of re-reading (P8). Delivery follows §5's era table
exactly: content changes are `notifications/resources/updated` in **both** eras,
established through `subscriptions/listen` with `resourceSubscriptions` in the
modern era and through `resources/subscribe` per URI in the legacy one.
`ttlMs` / `cacheScope` apply to list results in the modern era only. A
list-changed notification is never used to signal that a document's contents
changed.
*Exit:* a client that subscribes, receives a coalesced update, and re-reads
converges on the same revision the app holds; golden transcripts exist for each
supported era; a document closed while subscribed produces a clean unsubscribe
rather than a dangling subscription.

**Phase 5 — Persistent grants and second adapter.**
Persistent per-configuration grants that survive an app restart, built on the
Phase 1 credential and on whatever isolation boundary §4.3 requires for
unattended use; sandbox/App Group decision; revocation and stale-socket regression tests; then evaluate ACP client
mode (§11).
*Exit:* a paired agent reconnects across an app restart without a new approval
sheet while an unpaired one still gets one; revoking a pairing takes effect on
an in-flight call; a stale socket left by a crashed instance is reclaimed only
after ownership and object-type checks.

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
  intervening edit must report `conflicted`; an encoding, BOM, line-ending, or
  profile change made *during* the off-main write leaves the document
  format-dirty rather than clean.
- **Atomicity tests.** A batch whose third edit fails leaves the document
  byte-identical, including its undo stack **and** every offset-based set the
  transaction contract names — bookmarks, color markers, edit marks, folds, and
  selections.
- **Encoding and line-ending fidelity.** Shift_JIS, EUC-JP, and UTF-8-with-BOM
  documents survive an agent edit round trip byte-identically outside the edited
  region **under a profile whose save policy does not transform content**. Under
  a transforming profile — trailing-whitespace trimming and final-newline
  insertion apply to the whole buffer, not the edited part — the expected result
  is the edited buffer put through that profile's full save transformation, and
  the test asserts that instead. Byte identity outside the edit is a property of
  the agent's edit, not a promise the save policy makes. CRLF documents keep CRLF on save while the protocol only ever carries
  LF. Payloads containing `\r` are rejected. Text unrepresentable in the target
  encoding is rejected at edit time. Mixed-ending documents are explicitly
  excluded from byte-identity and are covered by their own test asserting the
  existing human choice still gates the save.
- **Save-race tests.** Text changed during the off-main prepare step fails at
  revalidation with nothing written. Text changed during the write itself leaves
  the document dirty, with disk identity refreshed and the saved baseline equal
  to `sourceSnapshot` — never to the newer buffer. A document whose save policy
  rewrote its text on the way out is still reported clean, matching today's
  behavior.
- **Metadata-precondition tests.** An encoding, BOM, or line-ending change with
  no text change invalidates a pending proposal and a stale `apply_edits`.
- **Ingress normalization tests.** One test per row of §3's ingress table — the
  initializer, recovery restore, new-from-template, the Insert Template command,
  `maru.document.setText`, multi-cursor and box paste, the conversion pipeline,
  typing, standard paste, IME commit, text drop, Find/Replace and Replace All,
  external-command output, and the generated grep-result document. Each stores
  LF; `read_document` never returns a CR.
- **Conflict precedence tests.** A call that violates two preconditions at once
  reports the §5.3 outcome with the higher precedence, and a metadata-only
  conflict does not force a re-read.
- **Era transcript tests.** For each supported era, golden transcripts for
  success, tool failure, cancellation, list invalidation, and document-content
  update — including that a modern-era failure carries both
  `resultType: "complete"` and `isError: true`, that a modern request without
  `clientInfo` is served rather than refused, and that every modern result
  stamps `serverInfo`.
- **Anchor bound tests.** Minting past the **per-connection** quota evicts
  oldest-first; an anchor does not survive a text revision change, a document
  close, or the connection ending; reconnecting does not inherit anchors;
  `withAnchors` and `anchorRanges` together are rejected.
- **Enumeration-scope tests.** Documents outside the grant appear in no listing,
  and the response does not reveal that anything was hidden.
- **Modal-freedom test.** No agent-initiated path reaches `runModal()`; asserted
  structurally, not by inspection.
- **Latency tests.** Typing latency under a concurrent full-document literal
  search and under a large `read_document` stays within the existing
  input-latency budget.
- **Concurrency-isolation build.** The new targets compile under strict
  concurrency checking, and no worker closure captures `Document`, a view
  controller, or an AppKit object.
- **Undo tests.** One tool call is one ⌘Z; review rejection restores exactly.
- **Authorization tests.** No agent-initiated path presents a window-modal
  sheet, approval included; a document opened after approval stays invisible
  until the human approves it or turns on the default-off inheritance switch;
  grants revoked mid-call take effect on the in-flight call; an unapproved connection cannot spam approval UI; a second bridge process
  gets its own approval rather than inheriting the first one's grant; a tool call
  from an unapproved connection returns promptly with a retryable error rather
  than waiting on the sheet; a document opened after approval is invisible until
  the human either approves it or turns on the opt-in inheritance switch.
- **Save fence tests.** A second *agent* save of the same document during an
  in-flight commit is refused with `save.in_progress`; a *human* ⌘S before the
  irreversible point supersedes the agent save, and after it runs automatically
  once finalization completes; a Save As during the fence cannot make a stale
  finalizer stamp identity from the wrong file; typing during the fence is never
  refused.
- **Retained-state tests.** Each bound in §7.1 fails with its structured error
  at the limit and not before; proposals expire at 10 minutes; rate limiting
  charges by bytes, not by request count.
- **Target-resolution tests.** An exposed command run with an explicit target
  acts on that target after the human switches tabs mid-call; `open_document`
  outside every authorized root is refused, including via a symlink that resolves
  outside one, and including when a path component is replaced between check and
  open.
- **Pairing tests.** An unpaired connection is refused before any document
  metadata is returned; a revoked credential stops working on its next call; a
  second MaruEdit instance gets its own endpoint and neither instance reclaims
  the other's live socket.
- **Range and truncation tests.** Half-open line ranges, an `endLine` past end of
  file, a `maxBytes` cut that would land inside a grapheme cluster, and an edit
  carrying both an anchor and offsets.
- **Undo ownership tests.** After an agent edit, ⌘Z produces the same result in
  every pane showing that document — or, if the refusal route was taken, the
  write was refused with `document.multiple_panes` before mutating anything.
- **Idempotency tests.** The same key with different arguments is refused; a
  cached conflict is returned rather than re-validated; records expire; a
  reconnect does not inherit them.
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

- **OQ-1 — Credential format and persistent-grant binding.** §4.3 fixes the
  pairing shape and Phase 1 implements it, so pairing itself is no longer open.
  What remains: credential format and rotation, behavior when the file is missing
  or stale, whether one configuration may hold credentials for several MaruEdit
  installations, and — for Phase 5's unattended persistent grants — which
  isolation boundary actually binds a credential to one program.
- **OQ-2 — Tracked anchors.** Should a later phase allow a write at a newer
  revision when every referenced anchor still validates? Requires boundary
  affinity, overlap semantics, lifetime, and memory bounds, and relates to
  ADR-007's finding that stale-anchor handling is the hard part of position
  tracking.
- **OQ-3 — Persistent-grant inheritance.** Does a *persistent* grant, once OQ-1
  exists, cover documents opened in a later session? This does not reopen the
  Phase 1 rule in §8.1(4), which is already decided: a grant **freezes at
  approval** and covers only the documents open at that moment. Later-opened
  documents are excluded unless the human turns on the per-connection
  inheritance switch, which is default off and lapses with the connection.
- **OQ-4 — Large documents.** What is the read budget, and does the answer need
  chunking beyond line ranges plus outline plus search?
- **OQ-5 — ~~Proposal expiry~~.** Resolved in §7.1: 10 minutes, no notification;
  the agent learns it from its next `review_status` poll.
- **OQ-6 — Untitled documents.** An agent cannot address an untitled buffer by
  path. Is `documentId`-only addressing sufficient in practice for the agents
  that will call?
- **OQ-7 — Streamable HTTP.** Does a containerised or remote agent ever need to
  reach MaruEdit? If yes, the answer is a separate ADR, not a flag.
- **OQ-8 — Regex bounding.** Which of the three options in §6.4 does MaruEdit
  take, and does a killable helper process justify its complexity for a text
  editor's search? This gates regex search in Phase 3, not Phase 0 or 1.

Resolved while writing this revision, and recorded here so the reasoning is not
lost: whether macros may keep inserting CR once LF becomes a model invariant.
They may not — §3 normalizes at every ingress and carves the macro behavior
change out of Phase 0's "observably identical" rule, because a buffer invariant
with one exception is not an invariant.

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
