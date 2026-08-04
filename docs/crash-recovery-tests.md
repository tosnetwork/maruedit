# Crash and Recovery Test Matrix

M7-07 is covered by deterministic fault simulations rather than force-quitting
the developer's running editor. All fixtures use isolated temporary paths or
throwaway `UserDefaults` suites.

| Failure | Automated evidence | Expected invariant |
|---|---|---|
| Termination during recovery write | `RecoveryStoreTests.testInterruptedWriteArtifactCannotReplaceLastCompleteRecovery` | An uncommitted sibling artifact is ignored and the last atomic record remains readable. |
| User-document save failure | `TextFileSaverTests.testWriteFailureLeavesOriginalFileIntact` | The original bytes remain unchanged. |
| Exit/cancel during Grep | `GrepServiceTests.testSwiftTaskCancellationBridgesIntoGrepToken` and `testCancellationStopsTraversalEarly` | The scan emits a cancelled final summary and stops traversal. |
| Corrupt preferences | `PreferencesStoreTests.testCorruptDataFallsBackToDefaultsWithoutCrashing` | Startup receives deterministic defaults. |
| Corrupt session | `SessionStoreTests.testCorruptFileIsQuarantinedNotLost` | Startup continues with an empty session and preserves corrupt bytes under a quarantine name. |
| Deleted, moved, modified, or replaced open file | `ExternalChangeDetectorTests` | The stale baseline is reported before a save can overwrite external work. |
| Multi-window close ordering | `DocumentControllerTests.testIndependentWindowControllersCanCloseInEitherOrder` | Per-window document ownership remains independent and each controller retains a valid blank tab. |
| Recovery versus source file | `RecoveryStoreTests.testRecoverySnapshotNeverWritesThroughToSourceFile` | Recovery writes only its Application Support record; source bytes are never changed automatically. |

The recovery store deliberately has no source-file URL in its schema. Restored
content becomes an unnamed, modified document and therefore requires an
explicit user save destination. This structural separation prevents crash
recovery from silently overwriting a source file.
