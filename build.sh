#!/bin/bash
set -euo pipefail

APP="MaruEdit"        # user-visible app/bundle name (unchanged since M0)
PRODUCT="MaruEditApp" # SwiftPM executable target name (see ROADMAP.md ADR-004)
BUILD=".build/release"
BUNDLE="${APP}.app"
VERSION="${VERSION:-0.1.0}"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  echo "Invalid VERSION: ${VERSION}" >&2
  exit 2
fi

echo "▸ Building ${APP} (release)…"
swift build -c release 2>&1

echo "▸ Packaging ${BUNDLE}…"
rm -rf "${BUNDLE}"
mkdir -p "${BUNDLE}/Contents/MacOS"
mkdir -p "${BUNDLE}/Contents/Resources"

# The compiled binary is named after the SwiftPM product (MaruEditApp) but
# ships inside the bundle under the CFBundleExecutable name (MaruEdit) so
# the process name, Activity Monitor, etc. stay user-facing as "MaruEdit".
cp "${BUILD}/${PRODUCT}" "${BUNDLE}/Contents/MacOS/${APP}"

# SwiftPM's generated Bundle.module accessor looks for this resource bundle
# beside the main .app bundle URL. Keep the generated name intact so bundled
# Help works after the application is moved away from the build directory.
RESOURCE_BUNDLE="MaruEdit_MaruEditApp.bundle"
RESOURCE_BUNDLE_PATH="$(find .build -path "*/release/${RESOURCE_BUNDLE}" -type d -print -quit)"
if [ -z "${RESOURCE_BUNDLE_PATH}" ]; then
  echo "Missing SwiftPM resource bundle: ${RESOURCE_BUNDLE}" >&2
  exit 1
fi
cp -R "${RESOURCE_BUNDLE_PATH}" "${BUNDLE}/${RESOURCE_BUNDLE}"
# Remove pre-PDF Help artifacts that may survive an incremental SwiftPM build.
rm -f "${BUNDLE}/${RESOURCE_BUNDLE}/user-guide.html" \
      "${BUNDLE}/${RESOURCE_BUNDLE}/macros.html" \
      "${BUNDLE}/${RESOURCE_BUNDLE}/key-bindings.html"

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
  <string>0.1.0</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
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

echo ""
echo "✓ Built ${BUNDLE} ($(du -sh "${BUNDLE}" | cut -f1) on disk)"
echo "  Run:  open ${BUNDLE}"
echo "  Copy: cp -r ${BUNDLE} /Applications/"
