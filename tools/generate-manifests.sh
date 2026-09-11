#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

ROOT="$(repo_root)"
VERSION="$(meson_option "$ROOT" manifest_format_version)"
ORIGIN="$(meson_option "$ROOT" manifest_base_url)"
APP_VERSION="$(awk -F"'" '/^[[:space:]]*version:/{print $2; exit}' "$ROOT/meson.build")"
OUT="${1:-"$ROOT/dist/manifests/$VERSION/manifest.json"}"

if ! command -v jq >/dev/null || ! command -v sha256sum >/dev/null; then
  echo "jq and sha256sum are required" >&2
  exit 1
fi

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
list="$workdir/files.json"
printf '[]' >"$list"

add_file() {
  local rel="$1"
  local abs="$2"
  local digest size
  digest="$(sha256sum "$abs" | awk '{print $1}')"
  size="$(wc -c <"$abs" | tr -d ' ')"
  jq --arg path "$rel" --arg sha "$digest" --argjson size "$size" \
    '. + [{path: $path, sha256: $sha, size: $size}]' "$list" >"$list.next"
  mv "$list.next" "$list"
}

while IFS=$'\t' read -r rel abs; do
  add_file "$rel" "$abs"
done < <(manifest_files "$ROOT")

while IFS= read -r file; do
  add_file "schemas/$(basename "$file")" "$file"
done < <(find "$ROOT/data/schemas" -maxdepth 1 -type f -name '*.json' | sort)

generated_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
revision="$(jq -r '[.[].sha256] | join("")' "$list" | sha256sum | awk '{print substr($1,1,16)}')"

mkdir -p "$(dirname "$OUT")"
jq -n \
  --arg schema "$ORIGIN/$VERSION/schemas/index.json" \
  --arg revision "$revision" \
  --arg generated_at "$generated_at" \
  --arg min_app_version "$APP_VERSION" \
  --argjson format_version "$VERSION" \
  --slurpfile files "$list" \
  '{
    "$schema": $schema,
    format_version: $format_version,
    revision: $revision,
    generated_at: $generated_at,
    min_app_version: $min_app_version,
    files: $files[0]
  }' >"$OUT"

echo "$OUT"
