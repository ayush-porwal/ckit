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
asset_name="Ckit-$version-arm64"
if [[ -e "$output" ]]; then
  printf 'Output already exists: %s. Move it aside or choose a new version.\n' "$output" >&2
  exit 1
fi
mkdir -p .build
package_stage="$(mktemp -d "$project_root/.build/release-stage.XXXXXX")"
cleanup() {
  rm -rf "$package_stage"
}
trap cleanup EXIT

xcodebuild \
  -project CKit.xcodeproj \
  -scheme CKit \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$package_stage/DerivedData" \
  -archivePath "$package_stage/CKit.xcarchive" \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
  MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build_number" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- \
  archive

app="$package_stage/CKit.xcarchive/Products/Applications/Ckit.app"
codesign --verify --deep --strict "$app"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")" == "$version" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")" == "$build_number" ]]
[[ "$(lipo -archs "$app/Contents/MacOS/Ckit")" == arm64 ]]

mkdir -p "$output"
ditto "$app" "$output/Ckit.app"
ditto -c -k --sequesterRsrc --keepParent "$output/Ckit.app" "$output/$asset_name.zip"
swiftc -parse-as-library CKit/Interface/PuffArtwork.swift Scripts/GenerateDMGArtwork.swift \
  -o "$package_stage/generate-dmg-artwork"
"$package_stage/generate-dmg-artwork" "$package_stage/background.tiff"
python3 -m venv "$package_stage/dmg-tools"
"$package_stage/dmg-tools/bin/python3" -m pip install --disable-pip-version-check \
  -r Scripts/dmg-requirements.txt
"$package_stage/dmg-tools/bin/dmgbuild" -s Scripts/DMGSettings.py \
  -D "app=$app" -D "background=$package_stage/background.tiff" \
  "Ckit $version" "$output/$asset_name.dmg"
hdiutil verify "$output/$asset_name.dmg"
(
  cd "$output"
  shasum -a 256 "$asset_name.dmg" "$asset_name.zip" > SHA256SUMS.txt
)
printf '\nRelease files: %s\n' "$output"
