# Release Rollback and Hotfix Procedure

## Stop or roll back

If signature/notarization, P0/P1, data-loss, startup, or artifact-integrity
evidence is wrong, immediately mark the GitHub release as a pre-release or
remove its downloadable artifacts, add a prominent release notice, and stop
promoting the DMG. Do not move or rewrite the signed tag. Preserve the bad
artifact/checksum privately for incident analysis and revoke the Developer ID
certificate only if its key or signing authority may be compromised.

The app has no automatic updater, so rollback cannot silently remove installed
copies. Publish explicit affected-version, backup, downgrade, and recovery
instructions. Never recommend overwriting documents to test a suspected
data-loss defect.

## Hotfix

1. Create `hotfix/1.0.x` from the affected signed tag.
2. Add a failing regression test and the smallest scoped fix.
3. Re-run every prior Gate, the four-runner CI matrix, security audit, Release
   and Universal build, P0/P1 audit, and relevant fault/performance tests.
4. Increment patch version and update CHANGELOG/release notes.
5. Sign, notarize, staple, Gatekeeper-test on a clean machine, checksum, and
   publish a new immutable tag/release through the normal release script.
6. Link the advisory and old release notice to the fixed version.

For a credential compromise, rotate/revoke credentials first and do not ship a
hotfix signed by a suspect identity. For a notarization outage, delay release;
do not publish an unsigned substitute under the same version.
