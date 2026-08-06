# Release Artifact Reproducibility

MaruEdit has no third-party Swift package dependencies. A release is built from
a tagged commit with the Xcode/Swift and macOS versions recorded in its release
notes. `scripts/build-release.sh` compiles both arm64 and x86_64 slices and
packages the deterministic source-controlled bundle metadata.

Reproduce the unsigned application:

```bash
git clone https://github.com/tosnetwork/maruedit.git
cd maruedit
git checkout v0.1.2
bash scripts/security-audit.sh
bash scripts/build-release.sh
lipo -archs MaruEdit.app/Contents/MacOS/MaruEdit
shasum -a 256 MaruEdit.app/Contents/MacOS/MaruEdit
```

Swift compiler and linker metadata can differ across toolchains, SDKs, and
absolute build paths, so byte-for-byte equality is guaranteed only when those
inputs match. Developer ID signing and notarization add Apple-issued metadata;
compare the unsigned executable first, then independently verify the published
artifact with `codesign --verify --deep --strict`, `spctl --assess`,
`stapler validate`, and the published DMG checksum.

The release report must record commit/tag, clean-tree status, `swift --version`,
`xcodebuild -version`, SDK/macOS version, architectures, audit/test results,
signing identity Team ID (not credentials), notarization result, and checksums.
