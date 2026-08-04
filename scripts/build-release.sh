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

echo "▸ Building ${APP} (release, arm64 + x86_64)…"
swift build -c release --arch arm64 --arch x86_64 2>&1

echo "▸ Verifying universal binary…"
lipo -info "${BUILD}/${PRODUCT}"

echo "▸ Packaging ${BUNDLE}…"
rm -rf "${BUNDLE}"
mkdir -p "${BUNDLE}/Contents/MacOS"
mkdir -p "${BUNDLE}/Contents/Resources"

cp "${BUILD}/${PRODUCT}" "${BUNDLE}/Contents/MacOS/${APP}"

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
  <string>1.0.0</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0</string>
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

echo ""
echo "✓ Built universal ${BUNDLE} ($(du -sh "${BUNDLE}" | cut -f1) on disk)"
echo "  Run:  open ${BUNDLE}"
echo "  Copy: cp -r ${BUNDLE} /Applications/"
