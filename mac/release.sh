#!/bin/bash
# Builds a signed, notarized, stapled MDSee release zip.
#
#   mac/release.sh 1.0.0            # build + notarize build/MDSee-1.0.0.zip
#   mac/release.sh 1.0.0 --publish  # …then create the GitHub release too
#
# One-time setup: store notarization credentials (asks for an app-specific
# password from appleid.apple.com):
#
#   xcrun notarytool store-credentials mdsee-notary \
#     --apple-id <your-apple-id> --team-id XCTTJJFCC6
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:?usage: release.sh <version> [--publish]}"
PUBLISH="${2:-}"
IDENTITY="${MDSEE_IDENTITY:-Developer ID Application}"
TEAM="${MDSEE_TEAM:-XCTTJJFCC6}"
PROFILE="${MDSEE_NOTARY_PROFILE:-mdsee-notary}"

if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
  echo "release: no 'Developer ID Application' certificate in the keychain." >&2
  exit 1
fi
if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
  echo "release: notary profile '$PROFILE' not found. Create it once with:" >&2
  echo "  xcrun notarytool store-credentials $PROFILE --apple-id <apple-id> --team-id XCTTJJFCC6" >&2
  exit 1
fi

echo "▸ building $VERSION (signed: $IDENTITY)"
xcodegen generate --quiet
xcodebuild -project MDSee.xcodeproj -scheme MDSee -configuration Release \
  -derivedDataPath build -quiet \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  DEVELOPMENT_TEAM="$TEAM" \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  MARKETING_VERSION="$VERSION" \
  build

APP="build/Build/Products/Release/MDSee.app"
ZIP="build/MDSee-$VERSION.zip"

echo "▸ notarizing"
ditto -c -k --keepParent "$APP" "$ZIP"
RESULT=$(xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait -f json)
SUBMISSION=$(echo "$RESULT" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')
STATUS=$(echo "$RESULT" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])')
if [ "$STATUS" != "Accepted" ]; then
  echo "release: notarization $STATUS — Apple's log follows" >&2
  xcrun notarytool log "$SUBMISSION" --keychain-profile "$PROFILE" >&2
  exit 1
fi

echo "▸ stapling"
xcrun stapler staple "$APP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "▸ verifying"
spctl -a -vv "$APP"
shasum -a 256 "$ZIP"

if [ "$PUBLISH" = "--publish" ]; then
  echo "▸ publishing GitHub release v$VERSION"
  gh release create "v$VERSION" "$ZIP" \
    --title "MDSee $VERSION" \
    --notes "Signed and notarized. Download, unzip, drag MDSee.app to Applications, open it once — then press space on a .md file."
fi

echo "done: $ZIP"
