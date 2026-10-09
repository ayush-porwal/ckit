#!/bin/bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  printf 'Usage: bash Scripts/CheckAppBundle.sh PATH_TO_CKIT_APP\n' >&2
  exit 1
fi
app="$(cd "$1" && pwd)"
executable="$app/Contents/MacOS/Ckit"
framework="$app/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle"

# Inspect the shipped executable, not a separately linked test fixture.
runpaths="$(otool -l "$executable" | awk '/cmd LC_RPATH/ { getline; getline; print $2 }')"
if ! printf '%s\n' "$runpaths" | /usr/bin/grep -Fxq '@executable_path/../Frameworks'; then
  printf 'Ckit is missing the runtime search path for its embedded frameworks.\n' >&2
  exit 1
fi
dependencies="$(otool -L "$executable")"
if ! printf '%s\n' "$dependencies" | /usr/bin/grep -Fq '@rpath/Sparkle.framework/Versions/B/Sparkle'; then
  printf 'Ckit is not linked to the expected Sparkle framework.\n' >&2
  exit 1
fi
if [[ ! -f "$framework" ]]; then
  printf 'The embedded Sparkle framework is missing.\n' >&2
  exit 1
fi
codesign --verify --deep --strict "$app"
# Reaching main proves dyld accepted the actual executable and its frameworks.
"$executable" --check-launch
printf 'App bundle framework loading and signing checks passed.\n'
