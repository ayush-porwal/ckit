#!/bin/bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  printf 'Usage: bash Scripts/GenerateAppcast.sh VERSION OUTPUT_DIRECTORY\n' >&2
  exit 1
fi
version="$1"
output="$(cd "$2" && pwd)"
asset="Ckit-$version-arm64"
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
stage="$(mktemp -d "${TMPDIR:-/tmp}/ckit-appcast.XXXXXX")"
trap 'rm -rf "$stage"' EXIT

# Pin the tooling to the same Sparkle release embedded in the app.
bash "$project_root/Scripts/FetchSparkle.sh" "$stage"
mkdir "$stage/updates"
ditto "$output/$asset.zip" "$stage/updates/$asset.zip"
printf '<p>Ckit %s for Apple Silicon Macs running macOS 26 or later.</p>\n' "$version" \
  > "$stage/updates/$asset.html"

signing=(--account dev.local.ckit)
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  # Use stdin, never a command-line argument or a checked-in key file.
  signing=(--ed-key-file -)
fi
printf '%s' "${SPARKLE_PRIVATE_KEY:-}" | "$stage/bin/generate_appcast" \
  "${signing[@]}" --maximum-deltas 0 --embed-release-notes \
  --download-url-prefix "https://github.com/ayush-porwal/ckit/releases/download/v$version/" \
  --link https://github.com/ayush-porwal/ckit \
  "$stage/updates"
ditto "$stage/updates/appcast.xml" "$output/appcast.xml"
# Reject a feed/archive signed with a different key before publishing anything.
python3 "$project_root/Scripts/VerifyAppcast.py" "$output/appcast.xml" \
  "$output/$asset.zip" "$project_root/Config/Updates.xcconfig"
