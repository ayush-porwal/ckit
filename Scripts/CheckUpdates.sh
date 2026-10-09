#!/bin/bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  printf 'Usage: bash Scripts/CheckUpdates.sh PATH_TO_CKIT_APP\n' >&2
  exit 1
fi
app="$(cd "$1" && pwd)"
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bash "$project_root/Scripts/CheckAppBundle.sh" "$app"
stage="$(mktemp -d "${TMPDIR:-/tmp}/ckit-update-fixture.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
# Archived frameworks omit compile-time headers; use the matching pinned SDK.
bash "$project_root/Scripts/FetchSparkle.sh" "$stage/sdk"
fixture="$stage/UpdateFixture.app"
mkdir -p "$fixture/Contents/MacOS" "$fixture/Contents/Frameworks"
ditto "$app/Contents/Frameworks/Sparkle.framework" "$fixture/Contents/Frameworks/Sparkle.framework"
ditto "$app/Contents/Info.plist" "$fixture/Contents/Info.plist"
plist="$fixture/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier dev.local.ckit.update-fixture' "$plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable UpdateFixture' "$plist"
/usr/libexec/PlistBuddy -c 'Set :SUEnableAutomaticChecks false' "$plist"
/usr/libexec/PlistBuddy -c 'Set :SUFeedURL https://updates.invalid/appcast.xml' "$plist"
cd "$project_root"
swiftc -parse-as-library CKit/Core/*.swift CKit/Interface/*.swift \
  CKit/ContainerMenuController.swift CKit/UpdateController.swift Scripts/CheckUpdates.swift \
  -F "$stage/sdk" -framework Sparkle \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  -o "$fixture/Contents/MacOS/UpdateFixture"
codesign --force --sign - "$fixture"
"$fixture/Contents/MacOS/UpdateFixture"
