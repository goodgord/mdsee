#!/bin/bash
# Builds MDSee from source and installs it to /Applications, registering the
# Quick Look extension. Building locally sidesteps Gatekeeper entirely — no
# quarantine, nothing to right-click-open.
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v xcodebuild >/dev/null; then
  echo "mdsee: Xcode is required — install it from the App Store first." >&2
  exit 1
fi
if ! command -v xcodegen >/dev/null; then
  echo "mdsee: xcodegen is required — brew install xcodegen" >&2
  exit 1
fi

echo "▸ generating project"
xcodegen generate --quiet

echo "▸ building (Release)"
xcodebuild -project MDSee.xcodeproj -scheme MDSee -configuration Release \
  -derivedDataPath build -quiet build

echo "▸ installing to /Applications"
rm -rf /Applications/MDSee.app
cp -R build/Build/Products/Release/MDSee.app /Applications/

echo "▸ registering the Quick Look extension"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f /Applications/MDSee.app
pluginkit -a /Applications/MDSee.app/Contents/PlugIns/MDSeeQuickLook.appex 2>/dev/null || true
pluginkit -e use -i com.goodgord.MDSee.QuickLook 2>/dev/null || true
qlmanage -r >/dev/null 2>&1 || true
qlmanage -r cache >/dev/null 2>&1 || true

echo
echo "Done. Press space on a .md file in Finder."
echo "If another markdown previewer still wins, pick MDSee under"
echo "System Settings → General → Login Items & Extensions → Quick Look."
