#!/bin/bash
# Builds and packages a Universal Binary (Apple Silicon arm64 + Intel x86_64)
# release .app, per ROADMAP.md's "Initial architectures" commitment (M0-04).
#
# This is slower than `build.sh` (compiles twice, once per architecture) and
# is meant for release/distribution builds, not everyday local iteration —
# use `build.sh` for that.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

APP="MaruEdit"        # user-visible app/bundle name (unchanged since M0)
PRODUCT="MaruEditApp" # SwiftPM executable target name (see ROADMAP.md ADR-004)
BUILD=".build/apple/Products/Release"
BUNDLE="${APP}.app"
VERSION="${VERSION:-0.1.1}"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  echo "Invalid VERSION: ${VERSION}" >&2
  exit 2
fi

echo "▸ Building ${APP} (release, arm64 + x86_64)…"
swift build -c release --arch arm64 --arch x86_64 2>&1

echo "▸ Verifying universal binary…"
lipo -info "${BUILD}/${PRODUCT}"

echo "▸ Packaging ${BUNDLE}…"
rm -rf "${BUNDLE}"
mkdir -p "${BUNDLE}/Contents/MacOS"
mkdir -p "${BUNDLE}/Contents/Resources"

cp "${BUILD}/${PRODUCT}" "${BUNDLE}/Contents/MacOS/${APP}"

RESOURCE_BUNDLE="MaruEdit_MaruEditApp.bundle"
RESOURCE_BUNDLE_PATH="${BUILD}/${RESOURCE_BUNDLE}"
if [ ! -d "${RESOURCE_BUNDLE_PATH}" ]; then
  echo "Missing SwiftPM resource bundle: ${RESOURCE_BUNDLE_PATH}" >&2
  exit 1
fi
ditto "${RESOURCE_BUNDLE_PATH}" "${BUNDLE}/Contents/Resources/${RESOURCE_BUNDLE}"

if [ -f "MaruEdit.icns" ]; then
  cp "MaruEdit.icns" "${BUNDLE}/Contents/Resources/AppIcon.icns"
fi

cat > "${BUNDLE}/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>MaruEdit</string>
  <key>CFBundleDisplayName</key>
  <string>MaruEdit</string>
  <key>CFBundleIdentifier</key>
  <string>network.tos.maruedit</string>
  <key>CFBundleVersion</key>
  <string>0.1.1</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.1</string>
  <key>CFBundleExecutable</key>
  <string>MaruEdit</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSSupportsAutomaticGraphicsSwitching</key>
  <true/>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key>
      <string>All Files</string>
      <key>CFBundleTypeRole</key>
      <string>Editor</string>
      <key>LSItemContentTypes</key>
      <array>
        <string>public.text</string>
        <string>public.plain-text</string>
        <string>public.source-code</string>
      </array>
    </dict>
  </array>
</dict>
</plist>
PLIST

/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VERSION}" "${BUNDLE}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${BUNDLE}/Contents/Info.plist"

# Seal the complete bundle for integrity. A future Developer ID release will
# replace this ad-hoc signature before notarization.
codesign --force --deep --sign - "${BUNDLE}"
codesign --verify --deep --strict --verbose=2 "${BUNDLE}"

echo ""
echo "✓ Built universal ${BUNDLE} ($(du -sh "${BUNDLE}" | cut -f1) on disk)"
echo "  Run:  open ${BUNDLE}"
echo "  Copy: cp -r ${BUNDLE} /Applications/"
