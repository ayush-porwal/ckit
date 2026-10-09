#!/bin/bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  printf 'Usage: bash Scripts/FetchSparkle.sh DESTINATION_DIRECTORY\n' >&2
  exit 1
fi
mkdir -p "$1"
curl --fail --location --silent --show-error \
  https://github.com/sparkle-project/Sparkle/releases/download/2.10.0/Sparkle-2.10.0.tar.xz \
  -o "$1/Sparkle.tar.xz"
printf '%s  %s\n' c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c \
  "$1/Sparkle.tar.xz" | shasum -a 256 -c -
tar -xf "$1/Sparkle.tar.xz" -C "$1"
