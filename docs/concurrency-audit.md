# Concurrency and Cancellation Audit

This audit records the M7-06 execution boundaries and the checks performed on
5 August 2026.

## Isolation boundaries

- AppKit state is main-actor state. `AppDelegate`, `AppCoordinator`, window and
  view controllers, UI delegate protocols, command definitions/registry, macro
  permission UI, and UI-facing managers are explicitly `@MainActor`.
- Grep owns no AppKit objects. Its synchronous scanner runs on a dedicated
  queue and communicates with immutable requests and value events. The async
  `GrepService.collect(_:)` adapter bridges Swift `Task` cancellation into the
  existing lock-protected `CancellationToken`. UI consumers explicitly hop to
  `MainActor` before updating controls.
- File loading and saving remain synchronous Core operations. Callers own queue
  selection; metadata preflight occurs before a read. Files at or above the
  reduced-features threshold are decoded and normalized on the window's
  dedicated file-I/O queue, then the completed document is transferred once to
  `MainActor`. Directory traversal is confined to Grep's worker queue. No Core
  file API captures UI objects.
- Each macro runs in a fresh JavaScriptCore context on the macro engine's serial
  queue. `MacroCommandBridge` is the only UI bridge and synchronously confines
  every AppKit access to the main queue. Completion handling and permission
  cleanup return to `MainActor`.
- External commands launch on the runner queue, read stdout and stderr on I/O
  queues, and deliver value chunks on the callback queue. UI handling is owned
  by the main-actor controller. The two output buffers are protected by one
  lock and are snapshotted only after both readers finish.
- Syntax highlighting performs regex work on a worker queue. Revision state is
  lock-protected; text storage and visual attributes are touched only on the
  callback/main queue. Stale revisions are discarded.

The source tree contains no `Task.detached` use. Background work receives value
data or an explicitly synchronized bridge, never an unguarded UI reference.

## Sendable review

A clean build with `-warn-concurrency` and
`-enable-actor-data-race-checks` completed with zero warnings. Every remaining
`@unchecked Sendable` type has an explicit synchronization contract:

- cancellation tokens and mutable process output use `NSLock`;
- macro and external-command engines confine mutable state to private queues;
- `MacroHost` and `MacroCommandBridge` expose callbacks whose UI accesses are
  synchronously confined to the main queue;
- syntax-highlight coordination uses a revision lock and confines the weak
  AppKit application object to its callback queue.

The audit also found and fixed a real strict-runtime failure: a JavaScriptCore
callback had inherited main-actor isolation while executing on the macro queue.
The callback is now nonisolated and crosses the documented bridge before any UI
access. App tests use asynchronous main-actor test entry points so XCTest runs
the actor-isolated code on the correct executor.

## Verification

- Normal suite: 394 tests, 0 failures.
- Thread Sanitizer: `swift test --sanitize=thread`; 394 tests, 0 failures, and
  no race reports (14.461 seconds test time).
- Strict clean build:
  `swift build --scratch-path /tmp/maruedit-m7-06-strict-2 -Xswiftc -warn-concurrency -Xswiftc -enable-actor-data-race-checks`;
  completed with zero warnings or errors.
- Task cancellation is covered by
  `GrepServiceTests.testSwiftTaskCancellationBridgesIntoGrepToken`, which
  cancels an in-flight async scan and verifies a cancelled summary before all
  files are scanned.
