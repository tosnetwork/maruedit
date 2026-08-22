# Release Artifact Reproducibility

MaruEdit has no third-party Swift package dependencies. A release is built from
a tagged commit with the Xcode/Swift and macOS versions recorded in its release
notes. `scripts/build-release.sh` compiles both arm64 and x86_64 slices and
packages the deterministic source-controlled bundle metadata.

Rebuilding from source is the strongest check available for a preview build,
and it is stronger than the published checksum: the DMG and its checksum come
from the same GitHub release, so anyone able to replace one can replace the
other. A local rebuild does not depend on that release being honest.

## Reproduce the unsigned application

Set `TAG` to the release being verified — this procedure is for whichever tag
you have, not only the newest one.

```bash
TAG=v0.1.6

git clone https://github.com/tosnetwork/maruedit.git
cd maruedit
git checkout "$TAG"
bash scripts/security-audit.sh
bash scripts/build-release.sh
```

A release ships **two** executables, and both have to be compared. Checking
only the app binary would leave the MCP bridge — which speaks to external
agents — unverified:

```bash
for binary in MaruEdit MaruEditMCPBridge; do
  # Not `path`: in zsh, macOS's default shell, `path` is tied to `PATH`, and
  # assigning a string to it leaves the shell unable to find any command.
  target="MaruEdit.app/Contents/MacOS/$binary"
  lipo -archs "$target"
  shasum -a 256 "$target"
done
```

Run the same commands on the binaries inside the published DMG and compare.

**Expect the digests to differ, and know what that does and does not mean.**
Swift embeds compiler and linker metadata that varies with the toolchain, the
SDK, and the absolute build path, so a local build and a CI build of the same
commit do not produce identical bytes. A mismatch under different build inputs
is *inconclusive*, not evidence of tampering — this is the normal result of
following this procedure on a different machine than the release was built on.

To get a comparison that means something, match the inputs recorded in the
release report (Swift version, Xcode version, SDK, macOS version) and build
from the same absolute path. Only then does a mismatch indicate that the
published binary is not what the tagged source produces.

The architecture list and the fact that both executables are present are
checkable regardless of toolchain, and are worth confirming on their own.

## Verifying the published artifact

What applies depends on how the release was signed, and running the wrong
checks produces failures that look like tampering but are not.

**Preview builds (ad-hoc signed, not notarized) — including 0.1.6.** Verify the
DMG checksum, and verify the bundle's internal consistency:

```bash
shasum -a 256 -c MaruEdit-<version>.dmg.sha256
codesign --verify --deep --strict --verbose=2 /Volumes/MaruEdit/MaruEdit.app
```

`codesign --verify` confirms the bundle matches its own seal — that nothing was
altered after it was built — which is a real check even for an ad-hoc
signature. It says nothing about *who* built it, because an ad-hoc signature
carries no identity.

Do **not** treat `spctl --assess` or `stapler validate` as verification here.
Both are expected to fail on a build that was never notarized:
`spctl --assess` reports `rejected` regardless of the quarantine attribute, and
`stapler validate` finds no ticket to staple. Neither outcome indicates a
damaged or tampered artifact.

**Signed releases (Developer ID plus notarization).** Once such a release
exists, add `spctl --assess`, `stapler validate`, and a check that the hardened
runtime is present on *every* Mach-O in the bundle, the nested bridge included —
the outer bundle's flags do not describe what is inside it.

## Release report

The release report must record commit/tag, clean-tree status, `swift --version`,
`xcodebuild -version`, SDK/macOS version, architectures of both executables,
audit/test results, signing identity Team ID (not credentials), notarization
result where applicable, and checksums.
