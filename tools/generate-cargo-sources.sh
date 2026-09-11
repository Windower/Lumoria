#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

ROOT="$(repo_root)"
LOCK="$ROOT/rust/native/Cargo.lock"
OUT="${1:-$ROOT/cargo-sources.json}"
GENERATOR_URL="https://raw.githubusercontent.com/flatpak/flatpak-builder-tools/master/cargo/flatpak-cargo-generator.py"

if [[ ! -f "$LOCK" ]]; then
  echo "missing $LOCK" >&2
  exit 1
fi

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

curl -fsSL "$GENERATOR_URL" -o "$workdir/flatpak-cargo-generator.py"

python3 -m venv "$workdir/venv"
"$workdir/venv/bin/pip" install --quiet --disable-pip-version-check aiohttp tomlkit
"$workdir/venv/bin/python" "$workdir/flatpak-cargo-generator.py" "$LOCK" -o "$OUT"

echo "Wrote $OUT"
