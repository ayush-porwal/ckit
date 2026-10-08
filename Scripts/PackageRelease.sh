#!/bin/bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  printf 'Usage: bash Scripts/PackageRelease.sh VERSION [BUILD_NUMBER]\n' >&2
  exit 1
fi
version="$1"
build_number="${2:-1}"
if [[ ! "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  printf 'Version must use X.Y.Z, for example 0.1.0.\n' >&2
  exit 1
fi
if [[ ! "$build_number" =~ ^[1-9][0-9]*$ ]]; then
  printf 'Build number must be a positive integer.\n' >&2
  exit 1
fi
if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then
  printf 'Packaging requires an Apple Silicon Mac with Xcode 27.\n' >&2
  exit 1
fi

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"
output="$project_root/dist/releases/v$version"
asset_name="CKit-$version-arm64"
if [[ -e "$output" ]]; then
  printf 'Output already exists: %s. Move it aside or choose a new version.\n' "$output" >&2
  exit 1
fi
mkdir -p .build
package_stage="$(mktemp -d "$project_root/.build/release-stage.XXXXXX")"
trap 'rm -rf "$package_stage"' EXIT

xcodebuild \
  -project CKit.xcodeproj \
  -scheme CKit \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath .build/release-derived \
  -archivePath "$package_stage/CKit.xcarchive" \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
  MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build_number" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- \
  archive

app="$package_stage/CKit.xcarchive/Products/Applications/CKit.app"
codesign --verify --deep --strict "$app"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")" == "$version" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")" == "$build_number" ]]
[[ "$(lipo -archs "$app/Contents/MacOS/CKit")" == arm64 ]]

mkdir -p "$package_stage/dmg" "$output"
ditto "$app" "$output/CKit.app"
ditto -c -k --sequesterRsrc --keepParent "$output/CKit.app" "$output/$asset_name.zip"
ditto "$app" "$package_stage/dmg/CKit.app"
ln -s /Applications "$package_stage/dmg/Applications"
hdiutil create -volname "CKit $version" -srcfolder "$package_stage/dmg" \
  -fs HFS+ -format UDZO "$output/$asset_name.dmg"
hdiutil verify "$output/$asset_name.dmg"
(
  cd "$output"
  shasum -a 256 "$asset_name.dmg" "$asset_name.zip" > SHA256SUMS.txt
)
printf '\nRelease files: %s\n' "$output"
