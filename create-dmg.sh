#!/bin/bash
set -euo pipefail

APP="MaruEdit"
BUNDLE="${APP}.app"
VERSION="${VERSION:-0.1.4}"
DMG="${APP}-${VERSION}.dmg"
STAGING="dmg-staging"
VOLUME_NAME="MaruEdit"

echo "▸ Step 1: Building Universal ${APP} ${VERSION}…"
VERSION="$VERSION" bash scripts/build-release.sh

if [ ! -d "${BUNDLE}" ]; then
  echo "✗ Build failed — ${BUNDLE} not found"
  exit 1
fi

echo "▸ Step 2: Verifying app bundle…"
PLIST="${BUNDLE}/Contents/Info.plist"
EXECUTABLE="${BUNDLE}/Contents/MacOS/${APP}"
RESOURCE_BUNDLE="${BUNDLE}/Contents/Resources/MaruEdit_MaruEditApp.bundle"

plutil -lint "${PLIST}"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${PLIST}")" = "${VERSION}"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${PLIST}")" = "${VERSION}"
ARCHS="$(lipo -archs "${EXECUTABLE}")"
[[ " ${ARCHS} " == *" arm64 "* && " ${ARCHS} " == *" x86_64 "* ]]
test -f "${RESOURCE_BUNDLE}/Contents/Resources/maruedit.pdf"
test -f "${RESOURCE_BUNDLE}/Contents/Resources/en.lproj/Localizable.strings"
test -f "${RESOURCE_BUNDLE}/Contents/Resources/ja.lproj/Localizable.strings"
codesign --verify --deep --strict --verbose=2 "${BUNDLE}"

if spctl --assess --type execute --verbose=2 "${BUNDLE}"; then
  echo "✓ Gatekeeper accepted ${BUNDLE}"
else
  echo "⚠ Gatekeeper rejection is expected for this ad-hoc, unnotarized preview" >&2
fi

echo "▸ Step 3: Creating DMG…"
rm -rf "${STAGING}" "${DMG}"

mkdir -p "${STAGING}"
cp -R "${BUNDLE}" "${STAGING}/"
cp LICENSE NOTICE.md UPSTREAM.md "${STAGING}/"
ln -s /Applications "${STAGING}/Applications"

hdiutil create \
  -volname "${VOLUME_NAME}" \
  -srcfolder "${STAGING}" \
  -ov \
  -format UDZO \
  "${DMG}"

rm -rf "${STAGING}"
shasum -a 256 "${DMG}" > "${DMG}.sha256"

SIZE=$(du -h "${DMG}" | cut -f1 | xargs)
echo ""
echo "✓ Created ${DMG} (${SIZE})"
echo "  SHA-256: ${DMG}.sha256"
echo "  Install: open ${DMG}"
