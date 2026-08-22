#!/bin/bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

VERSION="${VERSION:-0.1.7}"
SIGNING_IDENTITY="${MARUEDIT_SIGNING_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
DIST="dist"
APP="MaruEdit.app"
DMG="${DIST}/MaruEdit-${VERSION}.dmg"

if [ -z "$SIGNING_IDENTITY" ]; then
  echo "error: set MARUEDIT_SIGNING_IDENTITY to a Developer ID Application identity" >&2
  exit 2
fi
if [ -z "$NOTARY_PROFILE" ]; then
  echo "error: set NOTARY_PROFILE to an xcrun notarytool keychain profile" >&2
  exit 2
fi
if ! security find-identity -v -p codesigning | grep -Fq "Developer ID Application: $SIGNING_IDENTITY" &&
   ! security find-identity -v -p codesigning | grep -Fq "\"$SIGNING_IDENTITY\""; then
  echo "error: the requested Developer ID signing identity is not available" >&2
  exit 2
fi

test -z "$(git status --porcelain --untracked-files=no)" || {
  echo "error: tracked worktree changes must be committed before release" >&2
  exit 2
}

bash scripts/security-audit.sh
bash scripts/beta-smoke.sh
bash scripts/build-release.sh

# Every Mach-O in the bundle needs the Developer ID identity, the hardened
# runtime, and a secure timestamp — notarization rejects the submission if any
# one of them is missing on any executable, and the nested bridge is an
# executable. Signing runs inside-out because the outer signature seals what is
# inside it.
BRIDGE="$APP/Contents/MacOS/MaruEditMCPBridge"
test -f "$BRIDGE" || { echo "error: $BRIDGE is missing from the bundle" >&2; exit 2; }
codesign --force --timestamp --options runtime --sign "$SIGNING_IDENTITY" "$BRIDGE"
codesign --force --timestamp --options runtime --sign "$SIGNING_IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign --display --verbose=4 "$APP" 2>&1 | grep -q 'flags=.*runtime'
# Checked separately: a nested binary without the hardened runtime is the exact
# failure this ordering exists to prevent, and the outer check cannot see it.
codesign --display --verbose=4 "$BRIDGE" 2>&1 | grep -q 'flags=.*runtime'

rm -rf "$DIST"
mkdir -p "$DIST/dmg-root"
ditto "$APP" "$DIST/dmg-root/$APP"
cp LICENSE NOTICE.md UPSTREAM.md "$DIST/dmg-root/"
ln -s /Applications "$DIST/dmg-root/Applications"
hdiutil create -volname "MaruEdit" -srcfolder "$DIST/dmg-root" -format UDZO -ov "$DMG"
rm -rf "$DIST/dmg-root"
codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$DMG"

xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"

shasum -a 256 "$DMG" > "$DMG.sha256"
echo "created $DMG and $DMG.sha256"
