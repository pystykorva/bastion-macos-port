#!/bin/bash
# Builds Tessu.app (universal, optimized) and a .dmg.
#   scripts/package.sh                 ad-hoc signed (runs on this Mac; Gatekeeper warns elsewhere)
#   SIGN_ID="Developer ID Application: Name (TEAMID)" scripts/package.sh
#   NOTARY_PROFILE=name SIGN_ID=... scripts/package.sh     also notarizes and staples
#
# Where Support messages go is NOT in the source. It comes from the developer's own machine at build time:
#   TESSU_FEEDBACK_EMAIL        e.g. support@example.com   (opens the user's mail app)
#   TESSU_FEEDBACK_ISSUES_URL   e.g. https://github.com/you/tessu/issues/new   (https only)
# set in the environment (CI secrets) or in an untracked file named .release.env next to this script's parent.
# A build without them has no feedback destination, so a fork can never deliver to the original developer.
set -euo pipefail
cd "$(dirname "$0")/.."

# .release.env is read as data, never sourced: only these two names are accepted, one KEY=value per line.
if [ -f .release.env ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in
      TESSU_FEEDBACK_EMAIL=*)      [ -z "${TESSU_FEEDBACK_EMAIL:-}" ]      && TESSU_FEEDBACK_EMAIL="${line#*=}" ;;
      TESSU_FEEDBACK_ISSUES_URL=*) [ -z "${TESSU_FEEDBACK_ISSUES_URL:-}" ] && TESSU_FEEDBACK_ISSUES_URL="${line#*=}" ;;
    esac
  done < .release.env
fi
FEEDBACK_EMAIL="${TESSU_FEEDBACK_EMAIL:-}"
FEEDBACK_ISSUES_URL="${TESSU_FEEDBACK_ISSUES_URL:-}"
# Reject anything that could break out of the XML value or is not a plausible address.
if [ -n "$FEEDBACK_EMAIL" ] && ! [[ "$FEEDBACK_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
  echo "TESSU_FEEDBACK_EMAIL is not a valid address" >&2; exit 1; fi
if [ -n "$FEEDBACK_ISSUES_URL" ] && ! [[ "$FEEDBACK_ISSUES_URL" =~ ^https://[A-Za-z0-9.-]+(:[0-9]+)?(/[A-Za-z0-9._~/%-]*)?$ ]]; then
  echo "TESSU_FEEDBACK_ISSUES_URL must be a plain https:// URL" >&2; exit 1; fi

VERSION="${VERSION:-1.0.0}"
BUILD="${BUILD:-$(date +%Y%m%d%H%M)}"
SIGN_ID="${SIGN_ID:--}"
APP="dist/Tessu.app"

echo "==> building (release, arm64 + x86_64)"
swift build -c release --arch arm64 --arch x86_64 --product Tessu >/dev/null
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Tessu"
[ -f "$BIN" ] || { echo "binary not found at $BIN" >&2; exit 1; }

echo "==> assembling $APP"
rm -rf dist && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Tessu"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" \
    -e "s|__FEEDBACK_EMAIL__|$FEEDBACK_EMAIL|" -e "s|__FEEDBACK_ISSUES_URL__|$FEEDBACK_ISSUES_URL|" \
    Resources/Info.plist > "$APP/Contents/Info.plist"
if [ -n "$FEEDBACK_EMAIL$FEEDBACK_ISSUES_URL" ]; then echo "==> feedback destination configured"; else echo "==> no feedback destination (fork-safe build)"; fi
# The icon is an Icon Composer document (Resources/Tessu.icon). actool turns it into Assets.car (the layered
# icon macOS 26 renders with glass) and Tessu.icns (the flat fallback for older systems).
ICON_OUT="$(mktemp -d)"
xcrun actool "$PWD/Resources/Tessu.icon" --compile "$ICON_OUT" --app-icon Tessu --platform macosx \
  --minimum-deployment-target 14.0 --output-partial-info-plist "$ICON_OUT/partial.plist" >/dev/null
cp "$ICON_OUT/Assets.car" "$ICON_OUT/Tessu.icns" "$APP/Contents/Resources/"
# MIT: the copyright and permission notices must accompany every copy, binaries included.
cp Resources/Legal/*.txt "$APP/Contents/Resources/"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> signing ($SIGN_ID)"
OPTS=(--force --sign "$SIGN_ID" --entitlements Resources/Tessu.entitlements)
[ "$SIGN_ID" != "-" ] && OPTS+=(--options runtime --timestamp)
codesign "${OPTS[@]}" "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "==> disk image"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/" && ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Tessu" -srcfolder "$STAGE" -ov -format UDZO "dist/Tessu-$VERSION.dmg" >/dev/null
[ "$SIGN_ID" != "-" ] && codesign --force --sign "$SIGN_ID" --timestamp "dist/Tessu-$VERSION.dmg"

if [ -n "${NOTARY_PROFILE:-}" ] && [ "$SIGN_ID" != "-" ]; then
  echo "==> notarizing"
  xcrun notarytool submit "dist/Tessu-$VERSION.dmg" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "dist/Tessu-$VERSION.dmg"
fi
echo "done: $APP  dist/Tessu-$VERSION.dmg"
du -sh "$APP" "dist/Tessu-$VERSION.dmg"
