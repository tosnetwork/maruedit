#!/bin/bash
set -euo pipefail

APP="MaruEdit"
BUNDLE="${APP}.app"
VERSION="${VERSION:-0.1.0}"
DMG="${APP}-${VERSION}.dmg"
STAGING="dmg-staging"
VOLUME_NAME="MaruEdit"

echo "▸ Step 1: Building Universal ${APP} ${VERSION}…"
VERSION="$VERSION" bash scripts/build-release.sh

if [ ! -d "${BUNDLE}" ]; then
  echo "✗ Build failed — ${BUNDLE} not found"
  exit 1
fi

echo "▸ Step 2: Creating DMG…"
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
