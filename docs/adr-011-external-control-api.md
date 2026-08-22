# ADR-011: External Control API

**Status:** Active, amended and profiled by [ADR-012](adr-012-ai-agent-automation.md)  
**Date:** 2026-08-08  
**Scope:** Local, out-of-process control of a running MaruEdit process

> This document remains normative for transport selection (§3), endpoint layout
> and permissions (§3.1), framing and message limits (§4.1–4.2), the main-actor
> boundary and cancellation semantics (§8), the trust-tier argument (§9.6),
> Command Registry exposure policy (§9.7), and the security invariants (§16).
>
> ADR-012 defines the AI agent profile over that base: it replaces the public
> wire protocol with MCP and re-derives the method catalog from how AI agents
> actually fail at text editing. It amends this document on the points listed in
> its §8.1 — which include reversing §7's exclusion of an MCP server, and
> narrowing the handshake, envelopes, method catalog (§6), and version
> negotiation (§11) below to the **private bridge↔app channel** rather than
> anything an agent sees. It also removes the writer lease and the
> `externalCommands.run` capability. Read this document for the transport and
> trust reasoning, ADR-012 for the interface.

## Biggest open design risk

The largest design risk is not the transport choice. It is that **same Unix user does not imply same trusted automation client**. A `0600` Unix socket isolates other OS users, but it does not distinguish the intended Python/Claude integration from another process already running as the current user. Process names are not trustworthy identities.

Therefore External Control should be disabled by default, use filesystem permissions plus a per-session authentication token, and later add revocable client capability grants before enabling writes or command execution. `commands.run` should be default-deny at the command-definition level rather than exposing the entire Command Registry.

## 1. Context

MaruEdit currently has two automation surfaces.

The macro engine runs JavaScript in a fresh JavaScriptCore VM/context for every invocation. It exposes a frozen, value-only `maru` object and does not expose AppKit, document/controller objects, filesystem APIs, network APIs, or arbitrary Objective-C objects. The current API version is `maru.apiVersion === 1`. See `docs/macro-api-v1.md`, `docs/macro-engine.md`, `Sources/MaruEditCore/Macros/MacroEngine.swift`, and `Sources/MaruEditCore/Macros/MacroHost.swift`.

The current macro host surface is:

- `maru.commands.run(commandID)`
- `maru.document.getText()`
- `maru.document.setText(string)`
- `maru.editor.getSelections()`
- `maru.editor.setSelections(ranges)`
- `maru.editor.replaceSelections(string)`
- `maru.clipboard.readText()`
- `maru.clipboard.writeText(string)`
- `maru.ui.message(value)`
- `maru.ui.prompt(message, initialValue)`
- `maru.undo.group(name, callback)`

Selection coordinates are zero-based UTF-16 offsets and lengths with `NSRange` semantics. `setSelections` rejects an empty range set or any range outside the current document. `replaceSelections` applies the same string to each normalized selection. See `docs/macro-api-v1.md`.

`MacroHost` represents these capabilities as narrow Swift closures. It does not expose AppKit objects to JavaScript. See `Sources/MaruEditCore/Macros/MacroHost.swift`.

`MacroCommandBridge` binds those closures to one editor. Every operation touching AppKit synchronously enters the main thread. Document replacement and selection replacement use the existing editor edit path rather than replacing TextKit objects directly. The bridge also blocks `external.*` command IDs unless the macro has the `externalCommands` permission. See `Sources/MaruEditApp/Macros/MacroCommandBridge.swift`.

External Commands are a separate trust tier. They launch an absolute executable, use stdin/stdout/stderr as the data boundary, avoid shell interpolation in direct mode, and require confirmation on every shell-mode invocation. Once launched, the subprocess has the invoking user's OS authority. See `docs/external-commands.md`, `Sources/MaruEditCore/ExternalCommands/ExternalCommandRunner.swift`, and `Sources/MaruEditApp/ExternalCommands/*`.

The security model explicitly treats External Commands as an escape from the macro sandbox. MaruEdit currently has no updater, telemetry client, or network listener. See `docs/security-threat-model.md`.

The Command Registry is main-actor isolated. Stable `CommandID` values are its public identity, and `execute` returns `false` for an unknown or currently disabled command. See `Sources/MaruEditApp/Commands/CommandRegistry.swift` and `Sources/MaruEditCore/Commands/CommandID.swift`.

MaruEdit now supports more than one managed window: `AppCoordinator` owns a primary `MainWindowController` plus additional controllers created by detached tabs. Each `DocumentController` owns the documents for one window. See `Sources/MaruEditApp/Application/AppCoordinator.swift` and `Sources/MaruEditApp/Documents/DocumentController.swift`.

`CommandContext`, however, still contains only the `AppCoordinator`; it does not identify an explicit target window. Targeted command execution therefore requires a real command-context change rather than relying on whichever window happens to be key. See `Sources/MaruEditApp/Commands/CommandContext.swift`.

The required new feature is an inbound control surface for an already-running MaruEdit process. A client must be able to retain a connection and perform multiple request/response cycles without launching a new MaruEdit process for every operation.

This ADR calls that surface the **External Control API**.

---

## 2. Decision summary

External Control will be a third automation tier:

1. **Macros** — in-process, sandboxed, value-only.
2. **External Control** — out-of-process, local-only, editor-scoped, value-only.
3. **External Commands** — explicit subprocess execution with full user OS authority.

External Control MUST NOT implicitly inherit the External Commands trust model.

The initial transport SHALL be a Unix domain stream socket.

The server SHALL be disabled by default and SHALL NOT create or bind its socket until explicitly enabled by the user.

The wire format SHALL use length-prefixed UTF-8 JSON messages with request IDs.

The server SHALL require authentication in addition to filesystem permissions.

The first externally released phase SHALL be read-only.

The existing `maru.*` behavior SHALL be factored through a shared typed Swift automation layer rather than independently reimplemented in the socket server.

Direct arbitrary filesystem reads/writes SHALL NOT be part of this API.

---

# 3. Transport

## 3.1 Decision: Unix domain stream socket

Use an `AF_UNIX`, `SOCK_STREAM` Unix domain socket.

The socket is local to the machine, naturally supports `listen`/`accept` and multiple concurrent clients, and is directly usable from Python through the standard `socket.AF_UNIX` API.

External Control SHALL NOT listen on an IP address.

In particular, it MUST NOT bind:

- `0.0.0.0`
- `::`
- a LAN interface
- a dynamically chosen externally reachable TCP interface

### Endpoint layout

The non-sandboxed implementation should use:

```text
~/Library/Application Support/MaruEdit/ExternalControl/
    endpoint.json
    control.sock
```

The directory MUST be owned by the current user and mode `0700`.

The socket MUST be owned by the current user and mode `0600`.

`endpoint.json` SHOULD contain only discovery information:

```json
{
  "pid": 12345,
  "serverInstanceID": "...",
  "socketPath": "...",
  "protocolMajor": 1
}
```

It MUST NOT contain the authentication token.

The server MUST validate the final Unix-socket path before binding. If the platform cannot represent the path, startup MUST fail closed rather than silently falling back to TCP.

Stale endpoint cleanup MUST verify ownership and object type before unlinking anything.

### App Sandbox

The Unix-socket path is deliberately not considered a permanent filesystem ABI.

If MaruEdit later adopts App Sandbox, IPC placement must be revisited. Apple documents Unix domain sockets as an App Group IPC mechanism and requires the socket path to live in the App Group container for that configuration.

Therefore:

- the protocol implementation MUST separate transport from method dispatch;
- callers MUST discover the endpoint rather than assume the socket location is permanent;
- App Sandbox adoption MAY require an App Group, helper, XPC broker, or different discovery mechanism.

This ADR does not claim that the proposed non-sandboxed path is automatically sandbox-compatible.

## 3.2 Rejected: named pipe / FIFO

A POSIX FIFO is local and simple for one-way streaming, but it is a poor fit for this API.

Interactive control requires:

- bidirectional communication;
- multiple clients;
- request correlation;
- independent disconnect handling;
- cancellation;
- server-initiated notifications.

A FIFO design would require separate request/response FIFOs per client or an additional multiplexing protocol. At that point it recreates less convenient socket semantics.

Rejected for v1.

## 3.3 Rejected: localhost TCP

Binding only to `127.0.0.1` or `::1` would be straightforward for Python clients and would naturally support multiple connections.

It is nevertheless the wrong default for MaruEdit because it creates a network listener where the current threat model explicitly has none.

It also makes accidental future widening of the bind address a meaningful security failure.

For sandboxed macOS applications, listening for TCP connections is controlled by the incoming-network server entitlement.

External Control does not need network reachability.

Rejected for v1.

Remote control over TCP, SSH forwarding, WebSocket, HTTP, MCP, or A2A is explicitly outside this ADR.

---

# 4. Wire protocol

## 4.1 Framing

Each message SHALL be:

```text
4-byte unsigned big-endian payload length
UTF-8 JSON payload
```

Newline-delimited JSON was considered.

It is simpler to inspect manually, but length-prefixing provides:

- an explicit allocation boundary before JSON decoding;
- reliable framing across partial socket reads;
- no requirement that encoded JSON remain on one physical line;
- a straightforward maximum-message-size check.

The protocol remains JSON because interoperability and debuggability are more important than minimizing a few bytes of local IPC overhead.

CBOR, MessagePack, Protobuf, and custom binary schemas are not required for v1.

## 4.2 Message-size limit

Protocol v1 SHALL reject any frame larger than **16 MiB** before JSON decoding.

This is intentionally lower than MaruEdit's maximum materialized file size. `LargeFilePolicy` currently has reduced-feature and confirmation thresholds and a maximum materialized size of 256 MiB. See `Sources/MaruEditCore/Documents/LargeFilePolicy.swift`.

Therefore `document.getText` MAY return `payload.tooLarge` for a large document.

Chunked large-document transfer is out of v1 scope. A later protocol minor version may add range/chunk methods without raising the general frame limit.

## 4.3 Requests

A request has an ID:

```json
{
  "type": "request",
  "id": "42",
  "method": "document.getText",
  "target": {
    "documentID": "..."
  },
  "params": {}
}
```

`id` MAY be a string or integer.

A client MUST NOT reuse an ID while the previous request with that ID remains unresolved.

## 4.4 Responses

Success:

```json
{
  "type": "response",
  "id": "42",
  "ok": true,
  "result": "...",
  "meta": {
    "documentRevision": 73
  }
}
```

Failure:

```json
{
  "type": "response",
  "id": "42",
  "ok": false,
  "error": {
    "code": "permission.denied",
    "message": "..."
  }
}
```

The server SHALL provide stable machine-readable error codes.

Human-readable `message` text is diagnostic and MUST NOT be parsed by clients.

Candidate v1 error codes include:

- `protocol.invalidFrame`
- `protocol.versionMismatch`
- `auth.required`
- `auth.failed`
- `permission.denied`
- `target.notFound`
- `target.notActive`
- `params.invalid`
- `payload.tooLarge`
- `state.conflict`
- `ui.busy`
- `server.busy`
- `request.cancelled`
- `request.timeout`
- `command.notAllowed`

## 4.5 Notifications

Server-initiated notifications use no request ID:

```json
{
  "type": "notification",
  "event": "document.changed",
  "params": {
    "documentID": "...",
    "documentRevision": 74,
    "source": "user"
  }
}
```

Notification transport is part of the protocol shape from the beginning, but subscriptions are not required for the first read-only rollout.

Potential events:

- `document.opened`
- `document.closed`
- `document.activated`
- `document.changed`
- `document.externalChangeDetected`
- `editor.selectionsChanged`
- `window.opened`
- `window.closed`
- `window.activated`

Notifications MUST be treated as hints to re-query state, not as a complete event-sourcing log.

## 4.6 Cancellation frame

Cancellation must not be queued behind the operation it is intended to cancel.

Use a control frame:

```json
{
  "type": "cancel",
  "requestID": "42"
}
```

Cancellation is best-effort.

It MUST NOT imply transaction rollback.

---

# 5. Target identity and revisions

The single-run macro API can assume one active editor.

An out-of-process connection cannot.

## 5.1 Opaque IDs

The server SHALL assign opaque, process-lifetime IDs for:

- `windowID`
- `documentID`
- `editorID`

IDs MUST NOT be:

- raw object pointers;
- tab indexes;
- filenames;
- filesystem paths.

A tab index is mutable and therefore unsuitable as identity.

`Document.recoveryID` already has a different lifecycle and purpose: it identifies crash-recovery state, including unnamed documents. It SHOULD NOT be reused as the public External Control document identifier. See `Sources/MaruEditApp/Document.swift`.

All External Control IDs become invalid when the MaruEdit server instance exits.

`control.hello` returns a `serverInstanceID` so clients can detect this condition.

## 5.2 Explicit targeting

Automation clients SHOULD explicitly target objects after enumeration.

Document operations use `documentID`.

Selection operations use `editorID`, because a selection belongs to an editor presentation, not merely to document text.

Commands use an explicit window/editor command context once targeted command support exists.

Omitting a target MUST NOT silently mean an arbitrary window.

A convenience `"active"` target MAY be supported, but its response MUST report the exact resolved IDs.

## 5.3 Revisions

Every externally addressable document SHALL have a monotonically increasing in-memory `documentRevision`.

Every externally addressable editor SHALL have a monotonically increasing `selectionRevision`.

Revisions increment for changes caused by:

- direct user editing;
- macros;
- External Commands that replace editor content;
- External Control;
- reload/replacement operations.

Read responses SHOULD return the applicable revisions in `meta`.

Mutating requests SHALL support preconditions outside the mirrored method parameters:

```json
{
  "precondition": {
    "documentRevision": 73,
    "selectionRevision": 18
  }
}
```

For External Control writes, revision preconditions SHOULD be mandatory.

This is a deliberate addition over the macro API. A macro executes against one short-lived current state; a persistent external client can otherwise read revision 73, allow the user to edit revision 74, then unknowingly overwrite that edit.

A mismatch returns `state.conflict` without applying the mutation.

---

# 6. Method catalog

## 6.1 Mirrored `maru.*` methods

Where a method has an existing macro equivalent, its data semantics SHALL remain the same.

### `document.getText`

Result:

```text
String
```

Same text as the existing active-document macro call.

The response additionally contains `documentRevision`.

### `document.setText`

Parameter:

```text
text: String
```

Replaces the complete target document through the same editor mutation path used by macros.

Requires a matching document revision.

Wire result is `null`; JSON has no equivalent of JavaScript `undefined`.

### `editor.getSelections`

Result:

```json
[
  { "location": 0, "length": 4 }
]
```

Coordinates remain zero-based UTF-16 `NSRange` coordinates.

No grapheme, scalar, byte, line/column, or Python-string-index semantics are introduced.

The response additionally contains `documentRevision` and `selectionRevision`.

### `editor.setSelections`

Uses the same validation rules as the macro surface:

- array must be non-empty;
- location and length must be non-negative;
- every range must fit the current UTF-16 document length.

Returns `false` for an invalid range set.

Requires the expected document revision.

### `editor.replaceSelections`

Replaces every normalized selection with the same string and leaves the resulting selections/cursors according to the existing editor behavior.

Requires both expected document and selection revisions.

### `clipboard.readText`

Returns the plain-text clipboard content or `""`.

### `clipboard.writeText`

Replaces plain-text clipboard contents.

### `ui.message`

Shows an application message.

External Control SHOULD accept a string rather than attempting to reproduce arbitrary JavaScript `String(value)` conversion across languages.

### `ui.prompt`

Parameters:

- `message`
- `initialValue`, default `""`

Returns:

- entered string; or
- `null` after cancellation.

### `commands.run`

Parameter:

```text
commandID: stable CommandID string
```

Once authorized and exposed, execution still goes through `CommandRegistry`.

Unknown or disabled commands return `false`, preserving macro semantics.

Authorization failure is different and returns `permission.denied` or `command.notAllowed`.

### `undo.group`

A callback cannot cross a process boundary.

Therefore the wire representation SHALL be a bounded operation batch:

```json
{
  "method": "undo.group",
  "params": {
    "name": "Agent edit",
    "operations": [
      {
        "method": "editor.replaceSelections",
        "params": { "text": "..." }
      }
    ]
  }
}
```

Rules:

- nested `undo.group` is not allowed;
- the target is fixed for the group;
- only explicitly undoable document/editor mutations are allowed;
- commands, file opening/closing, clipboard access, and UI calls are excluded from a group;
- the server closes the native Undo group with `defer`/equivalent cleanup semantics even after an error;
- a runtime failure does not imply transactional rollback of preceding operations.

This preserves the semantic purpose of `maru.undo.group` without maintaining an open native Undo group across arbitrary socket round trips.

## 6.2 Necessarily new methods

### `windows.list`

Enumerates managed MaruEdit windows.

Returns opaque IDs plus non-sensitive presentation metadata.

### `documents.list`

Enumerates documents across managed windows.

Candidate fields:

- `documentID`
- `windowID`
- display name
- backing path or `null`, when authorized
- `isModified`
- `isUntitled`
- `isReadOnly`
- `largeFileMode`
- `documentRevision`

`DocumentController` already owns document lifecycle per window and de-duplicates an already-open URL inside that window. External Control should use that lifecycle rather than creating a separate document collection. See `Sources/MaruEditApp/Documents/DocumentController.swift`.

### `editors.list`

Enumerates editor presentations/panes for a window and identifies which document each editor currently displays.

This is required because editor selection is presentation-specific.

### `documents.open`

Opens an absolute file URL/path through MaruEdit's normal document-opening path.

It MUST NOT load the file independently in the socket server.

The normal open path already performs encoding, file-type, read-only, large-file, and file-metadata handling. See `Sources/MaruEditApp/Document.swift` and `Sources/MaruEditApp/Documents/DocumentController.swift`.

Default disposition:

```text
reuse if already open in target window;
otherwise create a new tab
```

Other dispositions can be added later.

### `documents.close`

Targets a document by ID.

Initial writable implementation SHOULD support:

```text
ifModified = "fail"
```

A remote caller MUST NOT silently discard modified user content.

Interactive `"prompt"` and explicitly authorized `"discard"` behavior can be considered later.

### `windows.activate`

Makes a specific managed window active.

This is UI-affecting and requires a separate permission.

Explicitly targeted document operations do not require activation.

### `documents.activate`

Selects the document's tab in its owning window.

Again, this is not required merely to read or modify a specifically targeted document.

### `events.subscribe`

Registers notification interests.

### `events.unsubscribe`

Removes subscription interests.

---

# 7. Explicit v1 exclusions

The following are NOT part of the first External Control release:

- arbitrary filesystem read;
- arbitrary filesystem write;
- directory traversal APIs;
- file deletion, rename, or chmod;
- shell execution;
- subprocess launch;
- direct External Command invocation;
- network access;
- HTTP server;
- WebSocket server;
- MCP server;
- A2A server;
- AppleScript;
- headless application mode;
- private AppKit objects;
- TextKit objects;
- direct `NSTextStorage` access;
- binary document transfer;
- files whose complete JSON response exceeds the frame limit;
- immediate FSEvents-style external-file notifications;
- extension/plugin loading;
- remote access from another machine.

The External Control API is not a general-purpose MaruEdit RPC for arbitrary internal methods.

---

# 8. Concurrency and threading

## 8.1 Main-actor boundary

Current UI/editor operations are main-thread confined. `MacroCommandBridge` explicitly synchronizes every AppKit access onto the main queue, and `CommandRegistry` itself is `@MainActor`.

External Control SHALL preserve that rule.

Socket accept/read/write, frame decoding, authentication, JSON serialization, and rate limiting run off the main actor.

The shared automation service runs on `MainActor`.

Conceptually:

```text
Unix socket
    ↓
frame decoder / session
    ↓
authorization + target resolution
    ↓
MainActor EditorAutomationService
    ↓
DocumentController / EditorViewController / CommandRegistry
```

A socket worker SHOULD use Swift concurrency/main-actor dispatch rather than duplicating `DispatchQueue.main.sync` throughout the new server.

## 8.2 Ordering

Requests from one connection are processed FIFO except for cancellation control frames.

For one client:

```text
request A accepted
request B accepted
```

means B does not observe a state older than the committed state of A.

Across different clients, arrival order at different sockets has no useful semantic meaning.

Mutating operations receive a monotonically increasing process-wide `operationSequence` when committed on the main actor.

Responses and relevant notifications SHOULD include that sequence.

## 8.3 Multiple clients

The transport SHOULD support multiple clients from the beginning.

Recommended initial limits:

- maximum 8 connected clients;
- maximum 32 queued requests per client;
- maximum 16 MiB per frame.

Read-only clients may coexist.

When mutation support arrives, MaruEdit SHOULD initially allow only one client to hold the write-control lease at a time.

This is simpler and safer than allowing two agents to race on the same editor.

Revision checks remain required even with a single external writer because the human user, macros, and External Commands can still modify the document.

Whether multi-writer control should ever be supported remains an open question.

## 8.4 Modal UI

This is a real constraint in the current application.

`MacroCommandBridge.ui.prompt` uses `NSAlert.runModal()`, and `MainWindowControllerExternalChangeTests` explicitly avoids an external-change branch because its modal `NSAlert` would block a headless test process.

External Control MUST NOT assume the main thread is always immediately available.

When an unrelated modal window is active:

- state-changing requests SHOULD return `ui.busy`;
- requests capable of showing another modal MUST return `ui.busy`;
- cancellation frames and socket-level control messages remain processable off-main.

They SHOULD NOT wait indefinitely behind a modal.

An API-owned `ui.prompt` is different. Its originating request may remain pending while the user responds.

Only one External Control interactive UI request may be active at a time.

A future implementation SHOULD prefer an API-owned asynchronous sheet/panel lifecycle over introducing another uncontrolled synchronous `runModal()` dependency.

## 8.5 Cancellation

Cancellation is cooperative and best-effort.

Possible states:

### Before main-actor dispatch

Cancel immediately.

No state is changed.

### Queued for main actor

Remove/cancel the queued operation where possible.

No state is changed.

### Mutation already committed

Cancellation is too late.

The mutation MUST NOT be silently rolled back.

The response MAY report `cancelTooLate` together with the committed operation/revision metadata.

### Long-running cooperative operation

Propagate a cancellation token to code that supports cancellation.

### `commands.run`

The current `CommandRegistry.execute` contract is synchronous and not cancellable.

Once a registry command has begun, External Control cannot promise cancellation.

Long-running cancellable commands would require a future Command Registry contract change.

This ADR does not pretend otherwise.

---

# 9. Security and permission model

## 9.1 Server disabled by default

External Control SHALL be disabled by default.

When disabled:

- no socket is bound;
- no endpoint file advertises a live endpoint;
- no authentication token exists;
- incoming control is impossible.

The Settings toggle is an explicit change to the application's current threat model.

Disabling the toggle SHALL:

- stop accepting clients;
- disconnect existing clients;
- invalidate the session token;
- remove the live socket;
- remove or mark stale endpoint metadata.

## 9.2 Filesystem permissions are necessary but not sufficient

Parent directory `0700` and socket `0600` establish an important OS-user boundary.

They do not distinguish:

```text
the Python tool the user intended to authorize
```

from:

```text
another process already running as the same Unix user
```

For an API capable of reading unsaved documents or clipboard contents, that distinction matters.

Therefore socket permissions SHALL NOT be the only authentication mechanism.

## 9.3 Session authentication

Every server enable/start SHALL generate a cryptographically random, high-entropy session token.

The token:

- exists only for the lifetime of that server session;
- is not written to `endpoint.json`;
- is not logged;
- is not included in diagnostics;
- rotates on restart;
- rotates when explicitly reset by the user.

The client presents it during the initial `control.hello`.

Settings MAY expose a **Copy Connection Token** action.

Clients SHOULD avoid passing the token as a process command-line argument where it may become visible through process inspection/history.

The session token is defense in depth, not a malware sandbox. A sufficiently privileged process running as the user may still attack the user's applications.

## 9.4 Process names are not identities

A client supplies diagnostic metadata:

```json
{
  "name": "Claude MaruEdit Tool",
  "version": "1.0"
}
```

This information is display-only.

MaruEdit MUST NOT grant permissions merely because a client claims a particular:

- process name;
- Python package name;
- PID;
- executable path.

For persistent per-client authorization, use an explicit client credential established by pairing.

A future pairing design may assign:

```text
clientID + secret/public-key credential
```

and store only the authorization record required to recognize that credential.

Exact credential mechanics are deferred, but display names are explicitly not authorization.

## 9.5 Capability permissions

External Control SHOULD use a dedicated permission model instead of directly reusing `MacroPermission`.

The current macro permissions are:

- `currentDocument`
- `clipboard`
- `otherFiles`
- `externalCommands`
- `network`

and are stored per macro ID and permission. See `Sources/MaruEditCore/Macros/MacroCatalog.swift` and `Sources/MaruEditCore/Macros/MacroPermissionStore.swift`.

Those categories are too coarse for a persistent external client.

Recommended External Control capabilities:

```text
windows.read
documents.read
documents.write
documents.open
documents.close
editor.readSelection
editor.writeSelection
clipboard.read
clipboard.write
commands.run
externalCommands.run
ui.present
events.subscribe
```

The persistence model MAY follow `MacroPermissionStore`'s versioned grant/revoke pattern, but it should use a separate `ExternalControlPermissionStore`.

A permission grant MUST be revocable from Settings without deleting client-side configuration.

## 9.6 Trust tier

External Control SHALL be treated as:

> externally reachable, but editor-scoped and value-only.

It is stronger than a macro because:

- the caller lives outside MaruEdit;
- the connection persists;
- the caller can perform multiple adaptive round trips;
- several clients may exist.

It is weaker than External Commands because it receives no primitive for:

- spawning processes;
- executing a shell;
- arbitrary filesystem access;
- arbitrary networking;
- AppKit object access.

This distinction is intentional.

A client process may itself have broad OS authority. That does not justify making broad MaruEdit authority automatically transitive through the control connection.

## 9.7 Command Registry exposure

`commands.run` is the highest-risk editor-scoped method because registry commands can have effects beyond editing text.

The current `CommandDefinition` has:

- ID;
- title;
- enablement closure;
- execute closure.

It has no external-exposure metadata. See `Sources/MaruEditApp/Commands/CommandDefinition.swift`.

Therefore External Control MUST NOT expose every registered command by default.

Recommended policy:

```text
external control exposure defaults to denied
```

A command must explicitly declare an External Control policy before remote execution.

Conceptually:

```text
denied
editorScoped
interactive
requires(capability)
```

The exact enum is an implementation detail.

The important invariant is default denial.

`external.user.*` commands created from External Commands configuration require the separate:

```text
externalCommands.run
```

capability.

This grant MUST be visibly higher risk because those commands intentionally escape the MaruEdit automation sandbox and run with user OS authority.

Existing shell-mode confirmation still applies.

## 9.8 Clipboard

Clipboard read and write permissions SHALL be separate.

Reading is a disclosure capability.

Writing can corrupt or replace user clipboard state.

Neither should be implied by document access.

## 9.9 `ui.message` and `ui.prompt`

External UI is not harmless.

An uncontrolled client could imitate application warnings or repeatedly interrupt the user.

`ui.prompt` can additionally cause the user to type sensitive information and return that information to the external client.

Therefore both belong behind `ui.present`.

Prompts initiated by External Control SHOULD visually identify the requesting client.

## 9.10 Abuse and rate limiting

A local authenticated client can still accidentally create denial-of-service behavior.

Example:

```text
while true:
    getText()
```

Recommended initial token-bucket limits per client:

- sustained: 30 requests/second;
- burst: 60 requests;
- maximum 32 pending requests.

Repeated violations return `server.busy` and may disconnect the client.

Notification storms SHOULD be coalesced.

For example, selection changes generated while a mouse drag is in progress need not emit hundreds of individual messages.

A 50 ms notification coalescing window is reasonable for interactive state.

Rate limiting is an availability mechanism, not an authorization boundary.

## 9.11 Undo behavior

Every individual External Control text mutation SHALL form one native undoable action.

Default action name:

```text
External Control
```

If a client needs several edits to be one undo step, it uses `undo.group`.

The implementation MUST NOT automatically merge remote edits into user edits based only on timing.

An agent performing ten edits per second must not make the user's own intervening keystrokes disappear into the same undo group.

---

# 10. Files and external-change detection

External Control SHALL NOT provide:

```text
files.read(path)
files.write(path)
```

or an equivalent arbitrary filesystem API.

`document.setText` modifies the open in-memory document.

Persistence must continue through MaruEdit's existing save path.

This is important because MaruEdit already records file identity and modification time and checks for external modification before same-file save. Its own successful save refreshes the baseline. See `Sources/MaruEditCore/Documents/ExternalChangeDetector.swift`, `Sources/MaruEditApp/Document.swift`, and `Sources/MaruEditApp/MainWindowController.swift`.

Therefore:

### External Control edits an open document

No external-change event occurs merely because in-memory text changed.

The document becomes modified normally.

### External Control later invokes an authorized save command

The existing save path remains responsible for external-change conflict handling.

### The Python client itself writes the backing file

That is an actual external modification.

MaruEdit will detect it at the next existing revalidation point.

### Notifications

`document.externalChangeDetected` MUST reflect that existing detection model.

`ExternalChangeDetector` currently performs revalidation rather than continuous filesystem watching.

Therefore the notification MUST NOT claim to be an immediate filesystem-watch event.

If immediate FSEvents-style monitoring is desired later, that is a separate feature.

### Future save method

If a dedicated `documents.save` method is added later, it MUST route through the same save/preflight/atomic-write behavior.

It MUST NOT call a raw socket-layer `Data.write`/`FileManager` path.

---

# 11. Protocol versioning and compatibility

The first request on every connection MUST be `control.hello`.

Example:

```json
{
  "type": "request",
  "id": "hello-1",
  "method": "control.hello",
  "params": {
    "protocolVersion": {
      "major": 1,
      "minor": 0
    },
    "maruApiVersion": 1,
    "token": "...",
    "client": {
      "name": "MaruEdit Python Client",
      "version": "0.1"
    },
    "requestedCapabilities": [
      "documents.read",
      "editor.readSelection"
    ]
  }
}
```

Successful response:

```json
{
  "type": "response",
  "id": "hello-1",
  "ok": true,
  "result": {
    "protocolVersion": {
      "major": 1,
      "minor": 0
    },
    "maruApiVersion": 1,
    "serverInstanceID": "...",
    "grantedCapabilities": [
      "documents.read",
      "editor.readSelection"
    ],
    "features": [
      "windows.list",
      "documents.list",
      "editors.list",
      "document.getText",
      "editor.getSelections"
    ],
    "maxFrameBytes": 16777216
  }
}
```

## 11.1 Two version dimensions

Keep two independent versions.

### `protocolVersion`

Covers:

- framing;
- handshake;
- envelopes;
- error behavior;
- target semantics;
- notifications.

Breaking changes increment `major`.

Additive changes increment `minor`.

### `maruApiVersion`

Reports which `maru.*` semantic contract the mirrored methods implement.

The current value is 1.

A protocol v1 server may expose only a subset of `maru` v1 during the phased rollout. Clients MUST inspect `features` and granted capabilities rather than infer completeness from `maruApiVersion`.

## 11.2 Negotiation

Major protocol mismatch:

```text
refuse connection
```

Minor mismatch:

```text
continue only when the client's required features are present
```

A client should explicitly declare required features.

Unknown additive JSON fields MUST be ignored.

Unknown methods MUST return a structured method-not-supported error.

---

# 12. Relationship to the existing macro implementation

## 12.1 Do not implement the socket API directly on `MacroHost`

`MacroHost` is intentionally shaped for one JavaScript macro execution.

It currently contains:

- closures bound to one active editor;
- string-based command IDs;
- selections serialized as JSON strings;
- synchronous UI callbacks.

That is appropriate for JavaScriptCore but not an appropriate multi-document RPC abstraction.

The socket server SHOULD NOT construct arbitrary `MacroHost` objects and treat them as the internal server API.

## 12.2 Extract a shared typed automation layer

Introduce an application-internal, value-only automation service.

Suggested boundary:

```text
Sources/MaruEditCore/Automation/
    AutomationRange.swift
    AutomationErrors.swift
    AutomationValueTypes.swift

Sources/MaruEditApp/Automation/
    EditorAutomationService.swift
    AutomationTargetRegistry.swift
```

`EditorAutomationService` is `@MainActor`.

It owns the authoritative implementation of:

- get/set document text;
- get/set selections;
- replace selections;
- clipboard access;
- command execution after policy checks;
- undo begin/end primitives;
- relevant UI capability calls.

The service consumes typed Swift values such as:

```text
AutomationRange(location: Int, length: Int)
```

not JSON strings.

## 12.3 Macro adapter

`Sources/MaruEditApp/Macros/MacroCommandBridge.swift` becomes an adapter:

```text
JavaScriptCore
    ↓
MacroHost closures
    ↓
EditorAutomationService
```

The bridge retains JS-specific responsibilities:

- JSON serialization needed by the existing `MacroHost`;
- mapping Swift failures to current JavaScript behavior;
- binding the current active editor;
- synchronous macro UI semantics.

`MacroEngine.swift` SHOULD require little or no protocol-related change.

Its JavaScriptCore VM lifecycle, `maru` bootstrap, Promise compatibility, cancellation checks, and no-network invariant remain separate from External Control.

## 12.4 External Control adapter

Add:

```text
Sources/MaruEditApp/ExternalControl/
    ExternalControlServer.swift
    ExternalControlSession.swift
    ExternalControlProtocol.swift
    ExternalControlAuthorization.swift
    ExternalControlPermissionStore.swift
```

Conceptually:

```text
socket request
    ↓
ExternalControlSession
    ↓
auth / permission / version / target checks
    ↓
EditorAutomationService
```

Transport-specific code never directly edits an `NSTextView`.

## 12.5 `AppCoordinator`

`AppCoordinator` SHOULD own External Control server lifecycle because it already owns:

- process-scoped application state;
- managed windows;
- Command Registry;
- preferences;
- macro host construction.

It is also the correct place to provide a narrow inventory of managed windows to `AutomationTargetRegistry`.

Do not make its private window-controller arrays public merely for the socket server.

Expose an intentional automation-facing accessor or registration mechanism.

## 12.6 Command targeting

`CommandContext` currently identifies only the coordinator.

Before External Control can safely execute commands against an arbitrary non-key window, command context must gain explicit target information.

Recommended direction:

```text
CommandContext
    coordinator
    targetWindow
    targetEditor/document as required
```

Command implementations must resolve their action through this context.

External Control SHOULD NOT temporarily steal keyboard focus merely to make an existing command accidentally target the requested window.

Until that refactor is complete, remotely executed commands should be limited to the active window or disabled entirely.

## 12.7 Permission persistence

Do not reuse `MacroPermissionStore` records.

Use its pattern:

- schema version;
- explicit grant/deny;
- revoke one;
- revoke all.

But External Control grants are keyed by a client identity/credential rather than a macro `CommandID`.

---

# 13. Phased rollout

## Phase 0 — Shared automation boundary, no listener

- [ ] Define typed automation ranges using zero-based UTF-16 offsets.
- [ ] Extract document/editor operations currently embedded in `MacroCommandBridge` into `EditorAutomationService`.
- [ ] Keep the existing JavaScript `maru.*` API byte-for-byte compatible at the observable level.
- [ ] Add tests comparing macro-path and direct-service text replacement behavior.
- [ ] Add tests comparing macro-path and direct-service selection validation.
- [ ] Add process-lifetime opaque window/document/editor IDs.
- [ ] Add monotonic document and selection revisions.
- [ ] Verify user edits and macro edits increment revisions.
- [ ] Do not create a socket.
- [ ] Do not change the existing threat model yet.

**Exit criterion:** existing macro tests pass and the same editor operations are callable through one shared typed Swift layer.

## Phase 1 — Authenticated read-only local control

- [ ] Add Settings master toggle, default OFF.
- [ ] Create no socket while the toggle is OFF.
- [ ] Bind an `AF_UNIX` stream socket only when enabled.
- [ ] Enforce `0700` endpoint directory and `0600` socket.
- [ ] Generate a new session token on every server start.
- [ ] Implement `control.hello`.
- [ ] Reject all non-handshake methods before successful authentication.
- [ ] Implement protocol major/minor negotiation.
- [ ] Enforce 16 MiB frame limit before JSON decoding.
- [ ] Implement `windows.list`.
- [ ] Implement `documents.list`.
- [ ] Implement `editors.list`.
- [ ] Implement `document.getText`.
- [ ] Implement `editor.getSelections`.
- [ ] Return revision metadata.
- [ ] Implement per-client FIFO ordering.
- [ ] Implement connection/request limits.
- [ ] Support multiple simultaneous read-only clients.
- [ ] Verify disabling External Control disconnects all sessions and removes the live socket.
- [ ] Verify restarting MaruEdit invalidates previous IDs and token.
- [ ] Verify a document over the payload limit returns `payload.tooLarge` without destabilizing the server.
- [ ] Add a Python interoperability smoke test using only Python's standard Unix-socket support.

**Exit criterion:** a local Python process can authenticate, enumerate current state, read a normal-size document, and read UTF-16 selections without being able to modify any MaruEdit state.

## Phase 2 — Scoped document/editor mutation

- [ ] Add persistent/revocable client authorization model.
- [ ] Add `documents.write`.
- [ ] Add `editor.writeSelection`.
- [ ] Require revision preconditions for mutations.
- [ ] Implement `document.setText`.
- [ ] Implement `editor.setSelections`.
- [ ] Implement `editor.replaceSelections`.
- [ ] Make each standalone mutation one native Undo action.
- [ ] Implement bounded `undo.group` operation batches.
- [ ] Auto-close every Undo group on error.
- [ ] Add one-writer control lease.
- [ ] Return `state.conflict` when the human user edits between client read and client write.
- [ ] Verify remote undo groups never absorb intervening user edits.
- [ ] Implement `documents.open` behind a separate capability.
- [ ] Route open through the existing document lifecycle.
- [ ] Implement safe `documents.close` with modified-document default `fail`.
- [ ] Do not add raw filesystem write.

**Exit criterion:** an authorized client can make conflict-aware, undoable changes while ordinary user edits remain protected from stale agent writes.

## Phase 3 — Commands, clipboard, and UI

- [ ] Add default-deny External Control exposure metadata/policy for commands.
- [ ] Refactor `CommandContext` to support explicit target windows.
- [ ] Implement `commands.run`.
- [ ] Preserve `false` for unknown/disabled commands.
- [ ] Return a permission error for non-exposed commands.
- [ ] Add separate `externalCommands.run` capability.
- [ ] Ensure `external.user.*` is inaccessible without that capability.
- [ ] Preserve existing shell-mode confirmation.
- [ ] Add `clipboard.read`.
- [ ] Add `clipboard.write`.
- [ ] Implement clipboard methods.
- [ ] Add `ui.present`.
- [ ] Implement `ui.message`.
- [ ] Implement one-at-a-time `ui.prompt`.
- [ ] Identify the requesting external client in interactive prompts.
- [ ] Return `ui.busy` instead of indefinitely stacking modals.
- [ ] Document that current synchronous registry commands cannot be cancelled after dispatch.

**Exit criterion:** no Registry command becomes externally reachable merely because it was registered.

## Phase 4 — Notifications and higher-volume clients

- [ ] Implement `events.subscribe`.
- [ ] Implement `events.unsubscribe`.
- [ ] Emit `document.changed`.
- [ ] Emit `editor.selectionsChanged`.
- [ ] Emit window/document lifecycle events.
- [ ] Coalesce high-frequency notifications.
- [ ] Include revision and operation sequence metadata.
- [ ] Emit `document.externalChangeDetected` only when existing revalidation detects the condition.
- [ ] Document that this is not a live filesystem watcher.
- [ ] Add reconnect/resubscribe tests.
- [ ] Evaluate chunked text transfer for documents larger than the v1 frame budget.

**Exit criterion:** a client can maintain a correct cached view by treating notifications as invalidation hints and re-reading authoritative state.

## Phase 5 — Sandbox/release hardening, if required

- [ ] Decide whether Mac App Store/App Sandbox support is a product requirement.
- [ ] If yes, design the App Group/XPC/helper strategy before promising endpoint-path compatibility.
- [ ] Verify arbitrary supported external clients can still connect under the chosen sandbox model.
- [ ] Threat-model client credential persistence.
- [ ] Add connected-client/revoke UI.
- [ ] Add security regression tests for stale sockets, malformed frames, invalid tokens, oversized frames, and permission downgrade/revocation.

---

# 14. Testing requirements

Protocol tests MUST include fragmented reads.

One logical frame must work when delivered as:

```text
1 byte
then 2 bytes
then remaining header
then payload fragments
```

The decoder must not assume one socket read equals one message.

Tests SHALL also cover:

- multiple frames in one socket read;
- zero-length/invalid frames;
- declared length above maximum;
- invalid UTF-8;
- invalid JSON;
- duplicate in-flight request ID;
- request before hello;
- invalid token;
- protocol major mismatch;
- unknown method;
- missing target;
- stale target ID;
- target invalidated by close;
- concurrent clients;
- queued-request cancellation;
- disconnect during request;
- client disconnect during `undo.group`;
- permission revocation while connected;
- app-side document edit causing revision conflict;
- UTF-16 offsets around emoji/surrogate pairs;
- multi-selection replacement;
- unnamed documents;
- read-only documents;
- reduced-feature large files;
- modal UI busy behavior.

Fuzzing the frame decoder is recommended before write capability is enabled.

No untrusted JSON value may cause an unchecked allocation proportional to an attacker-controlled declared size.

---

# 15. Alternatives rejected

## Reuse External Commands with a long-running subprocess

Rejected.

External Commands are initiated from MaruEdit and communicate with one subprocess run through stdio.

The required direction is the opposite: an independently running client must initiate multiple interactions with the already-running editor.

Keeping a subprocess alive would also invert ownership incorrectly and would not solve generic client discovery.

## Run a JavaScript macro for each request

Rejected.

Macros are intentionally short-lived and receive a fresh JavaScript VM/context per run.

They do not provide a persistent external connection or multi-document target identity.

## Add HTTP/REST on localhost

Rejected for v1.

It introduces an IP network listener for no functional requirement that Unix-domain IPC cannot satisfy.

## AppleScript only

Rejected as the primary API.

AppleScript could be a future user-facing automation surface, but it does not directly solve the requested Python/tool-loop protocol, capability negotiation, revision checks, multi-client sessions, and notification model.

## XPC as the public client protocol

Not selected for v1.

XPC has strong macOS integration but makes an arbitrary Python client materially harder and couples the API to Apple-specific client tooling.

It remains a plausible internal transport/broker if future App Sandbox requirements demand it.

## Expose `MacroHost` itself over JSON

Rejected.

`MacroHost` is a per-run closure bridge, not a multi-window domain model. It also serializes selections as JSON specifically for the JavaScript adapter.

The shared boundary should be below `MacroHost`, not above it.

---

# 16. Security invariants

The following are normative.

1. External Control is OFF by default.
2. OFF means no listening endpoint exists.
3. Protocol v1 never opens a TCP listener.
4. The server never binds a non-local network interface.
5. Unix socket permissions are restrictive.
6. Successful local socket connection alone does not imply authorization.
7. Authentication is required before document metadata is returned.
8. Client-supplied process names are not trusted identities.
9. Permission checks occur before main-actor side effects.
10. Unknown Registry commands are not converted into arbitrary selector lookup.
11. Registered commands are not externally exposed by default.
12. External Commands require a separate high-risk capability.
13. No AppKit or TextKit object crosses the protocol.
14. Selection coordinates remain UTF-16 `NSRange` coordinates.
15. No arbitrary filesystem API is introduced.
16. Document persistence uses existing save/conflict machinery.
17. Stale revision writes fail without modifying the document.
18. Cancellation never silently pretends to roll back an already committed edit.
19. Undo groups are closed on every exit path.
20. Authentication tokens and document payloads are never emitted through telemetry or routine protocol logs.

---

# 17. Open questions

The following require maintainer decisions before write-capable implementation starts.

## OQ-1: Persistent client identity

Is an ephemeral per-MarueEdit-session token sufficient for the intended workflow, or must a Python/Claude integration be able to reconnect across app restarts without user interaction?

If persistence is required, define a pairing credential rather than trusting executable/process names.

**Recommended:** ephemeral token for Phase 1; explicit paired credentials before persistent write grants.

## OQ-2: Multiple writers

Should two external clients ever be allowed to modify documents concurrently?

**Recommended:** multiple readers, one external writer lease.

Keep revision checks regardless.

## OQ-3: File opening authority

Should a paired client with `documents.open` be allowed to ask MaruEdit to open any absolute path MaruEdit itself can access, or only files/directories previously authorized through the UI?

This becomes significantly more important if MaruEdit later adopts App Sandbox.

## OQ-4: Modified-document close behavior

Should External Control ever be permitted to request:

```text
discard unsaved changes
```

without an on-screen confirmation?

**Recommended:** not initially.

## OQ-5: Command exposure policy

Should exposure metadata live:

- directly on `CommandDefinition`; or
- in an External Control policy table keyed by `CommandID`?

**Recommended:** make exposure an explicit property of command definition once the design is mature, with default `.denied`.

## OQ-6: External Commands

Is a persistent `externalCommands.run` grant acceptable, or should direct External Command execution always require per-run confirmation when triggered from External Control?

**Recommended:** require a dedicated high-risk client grant; preserve the existing every-run confirmation for shell mode.

## OQ-7: `ui.prompt`

Is remote prompting useful enough to justify its spoofing/phishing surface?

If retained, the prompt should visibly state the requesting client identity.

## OQ-8: Exact Settings UI

Need final copy for at least:

- Enable External Control API
- Copy Connection Token
- Reset Connection Token
- Connected Clients
- Granted Permissions
- Revoke Client
- Disconnect Client

The UI should make clear that enabling the API allows local processes to request access to open editor content.

## OQ-9: Large document transport

Is complete retrieval of 16–256 MiB documents a required first-class use case?

If yes, design UTF-16-aware chunk/range transfer rather than increasing unrestricted JSON frame sizes.

## OQ-10: Sandbox target

Is eventual Mac App Store/App Sandbox compatibility a hard requirement?

If yes, endpoint/discovery architecture should be finalized with the App Group/XPC constraints before declaring the external transport stable.

## OQ-11: Supported client languages

The wire protocol is intentionally language-neutral.

Is MaruEdit committing only to:

```text
documented protocol + Python reference client
```

or to supported SDKs for additional languages?

**Recommended:** protocol first; Python reference client only.

## OQ-12: Public stability level

Should External Control protocol v1 be a supported compatibility contract immediately, or ship first behind an Experimental setting?

**Recommended:** Experimental through the read-only and first write-capable releases, while still applying protocol versioning from day one.

---

# 18. Final recommendation

Implement External Control as a local Unix-domain, authenticated, capability-scoped control surface over a shared value-only editor automation service.

Do not make External Commands remotely invokable by default.

Do not expose the entire Command Registry by default.

Do not add a filesystem API.

Do not rely on active-window state for persistent clients.

Do not use process names as authorization identity.

Ship read-only first.

Before enabling mutations, add:

- stable process-lifetime target IDs;
- revisions and stale-write rejection;
- explicit client grants;
- one-writer lease;
- native undo boundaries.

This preserves the important property of the existing `maru.*` design: automation receives narrow values and capabilities rather than MaruEdit's internal AppKit object graph, while adding the minimum new machinery required for a persistent out-of-process controller.
