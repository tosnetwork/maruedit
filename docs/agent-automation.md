# Agent Automation

MaruEdit can expose the documents you have open to an AI agent over the
[Model Context Protocol](https://modelcontextprotocol.io). The agent reads the
live buffer rather than the file on disk, and every edit it makes is one undo
entry you can press ⌘Z on.

The interface is **off by default**. Turning it on is not the same as granting
access: a client must also pair, be approved, and be given each capability it
uses.

Design rationale and the full protocol contract are in
[ADR-012](adr-012-ai-agent-automation.md).

## Turning it on

1. **Settings > Advanced > Allow AI agents to connect.**
   MaruEdit then listens on a private per-user socket under
   `~/Library/Application Support/MaruEdit/`. Nothing is reachable over the
   network.
2. **Other > Agent Connections…** opens the window where connections are
   approved, capabilities are granted, pending edits are reviewed, and pairings
   are revoked. It also shows recent activity.

Switching the setting off stops the listener and drops live connections.

## The bridge

An MCP stdio server is spawned by its client, and a running GUI application
cannot be anyone's child process. MaruEdit therefore ships a small bridge
inside the app bundle:

```
/Applications/MaruEdit.app/Contents/MacOS/MaruEditMCPBridge
```

The bridge holds connection state and nothing else — documents, revisions, and
pending edits live in MaruEdit, and every handle the bridge relays is opaque to
it. It answers `tools/list` even when MaruEdit is not running, so an agent's
tool list does not appear and disappear with the editor.

## Pairing

Each agent configuration pairs once:

```bash
/Applications/MaruEdit.app/Contents/MacOS/MaruEditMCPBridge --pair
```

MaruEdit shows a verification code. Confirm the codes match in **Agent
Connections…**, and the bridge prints a credential identifier. Add it to the
agent's MCP server configuration:

```json
{
  "mcpServers": {
    "maruedit": {
      "command": "/Applications/MaruEdit.app/Contents/MacOS/MaruEditMCPBridge",
      "args": ["--credential-id", "<identifier from pairing>"]
    }
  }
}
```

`--credential-id` is an identifier, not a secret. The secret itself never
appears in a config file, a shell history, or a backup:

- On a **Developer ID signed build**, it is stored in your Keychain, and macOS
  releases it only to MaruEdit and its bundled bridge.
- On a **build without a stable code signature** — including local builds and
  the current preview DMGs — it is stored in a `0600` file instead, because a
  Keychain item would stop working on every update. Any program running as you
  can read that file, so treat such a pairing as a record of what you approved,
  not as a lock.

Pairing tells you which backend was used. **Revoke pairing** in Agent
Connections… invalidates a credential; the configuration must pair again.

Other bridge options: `--client-name <name>` (or `MARUEDIT_CLIENT_NAME`) sets
the display name shown for the connection, and `--instance <id>` selects one
running MaruEdit. With two copies running, discovery fails closed and names the
instance ids rather than guessing which documents to expose.

## Grants

Approving a connection grants **reading only** — document text and selections —
and nothing else. The grant is frozen to the documents already open at that
moment; a grant that silently grew would turn "read what I have open" into
"read anything I open". **Include documents I open next** is a separate opt-in
that lapses when the connection ends.

Each further capability is its own checkbox on the connection:

| Checkbox | Unlocks |
|---|---|
| *(Approve)* | `list_documents`, `list_editors`, `read_document`, `get_outline`, `search_documents`, `get_selection` |
| Edit documents | `apply_edits`, `review_status` |
| Move the cursor | `set_selection`, `reveal` |
| Save | `save_document` |
| Open files | `open_document` |
| Run commands | `run_command` |

A tool with no capability granted is refused, and a tool absent from that table
is refused rather than allowed by default.

**Skip approval next time** remembers the decision for a paired configuration,
so a reconnect does not need the approval click again. **Revoke** drops the
grant immediately, including for a call already in flight.

## Reviewing edits

Edits are queued for you by default. They appear under **Edits waiting for your
review** with Apply and Reject; the agent polls `review_status` to learn what
happened. **Apply edits without review** switches that connection to applying
directly — still one undo entry per call.

## Opening files

`open_document` works only inside folders you authorize with **Add folder…**.
Without one, opening files is unavailable rather than unrestricted. Roots are
per connection, so a folder authorized for one configuration does not authorize
another. Paths that leave a root, symbolic links pointing out of one, non-files,
and oversized files are all refused with a distinct reason.

## Revisions

Every read returns the revisions it was computed against, and every write must
pass them back:

- `baseRevision` — the document text
- `baseMetadataRevision` — encoding and line endings
- `baseSelectionRevision` — a pane's selection

If you typed since the agent read, the call is refused and told the current
state instead of overwriting your work. `apply_edits` applies all of its edits
or none. An `idempotencyKey` makes a retry return the first outcome rather than
editing twice.

Text crossing this interface always uses LF, whatever the document saves as.
Line numbers are one-based; `endLine` is exclusive.

## Tools

| Tool | Purpose |
|---|---|
| `list_documents` | Open documents, their revisions, and whether the buffer differs from disk |
| `list_editors` | Visible panes; a split shows one document in two panes with independent cursors |
| `read_document` | Buffer text, optionally a line range, with byte-capped and reported truncation |
| `get_outline` | Headings and symbols with line numbers |
| `search_documents` | Literal or regex search across granted documents, with context |
| `get_selection` | What is selected in a pane |
| `apply_edits` | Atomic, revision-checked edit; one undo entry |
| `review_status` | Whether a queued edit was applied, rejected, conflicted, or expired |
| `set_selection` | Move the cursor and selection |
| `reveal` | Scroll a line into view without moving the cursor |
| `open_document` | Open a file from an authorized folder |
| `save_document` | Save after a non-interactive preflight |
| `run_command` | Run an exposed editor command |

Selections are addressed by editor, never by document, because a split has two
independent cursors on one document.

`run_command` is default-deny and independent of the command registry:
registering a command does not make it remotely invocable. A command must act
synchronously to be exposed, so a target window stated by the caller still
applies when the work runs. As of 0.1.8 the only exposed command is `file.new`.

`save_document` never resolves a conflict silently. If the file changed
underneath, the encoding cannot represent the text, or the document needs a
Save As, the agent is told which — you are not interrupted by a dialog raised
on its behalf.

## Refusals worth knowing

- **Regular expressions that can backtrack exponentially** — an unbounded
  quantifier around another one, or around a group containing `|` — are refused
  with an explanation. A started match has no cancellation point. Bound the
  repetition (`a{1,64}`) or use a character class. What does run is bounded, and
  the number of abandoned runs is capped.
- **Reading a document by path** is the wrong move and the tool descriptions say
  so: while a buffer is dirty the file on disk is out of date, and an untitled
  document has no path at all.
- **An in-place save is refused if the file was replaced underneath.** A document
  an agent opened records the identity of the file it actually read.

## Security

The threat model, including what this interface does and does not defend
against, is in [Security](security-threat-model.md). In short: the interface is
off until you turn it on, local-socket only, paired per configuration,
approved per connection, granted per capability, frozen to the documents you
had open, and revocable at any time.
