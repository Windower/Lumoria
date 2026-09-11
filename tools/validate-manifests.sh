#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

ROOT="$(repo_root)"
SCHEMAS="$ROOT/data/schemas"
LOCAL_SCHEMAS="$(mktemp -d)"
failed=0

if ! command -v pipx >/dev/null; then
  echo "pipx is required to run check-jsonschema" >&2
  exit 1
fi

python3 - "$SCHEMAS" "$LOCAL_SCHEMAS" <<'PY'
import json
import sys
from pathlib import Path

src, dest = Path(sys.argv[1]), Path(sys.argv[2])
for path in sorted(src.glob("*.json")):
    data = json.loads(path.read_text())
    data["$id"] = (dest / path.name).resolve().as_uri()
    (dest / path.name).write_text(json.dumps(data, indent=2) + "\n")
PY

schema_file() {
  printf '%s/%s' "$LOCAL_SCHEMAS" "$(basename "$1")"
}

validate() {
  local schema
  schema="$(schema_file "$1")"
  shift
  if ! pipx run check-jsonschema --schemafile "$schema" --base-uri "file://$LOCAL_SCHEMAS/" "$@"; then
    failed=1
  fi
}

declare -A batches
while IFS=$'\t' read -r rel abs; do
  schema="$(schema_for "$rel")"
  if [ ! -f "$SCHEMAS/$schema" ]; then
    echo "no schema $schema for $rel" >&2
    failed=1
    continue
  fi
  batches[$schema]+="$abs"$'\n'
done < <(manifest_files "$ROOT")

for schema in $(printf '%s\n' "${!batches[@]}" | LC_ALL=C sort); do
  mapfile -t files <<<"${batches[$schema]%$'\n'}"
  validate "$SCHEMAS/$schema" "${files[@]}"
done

root="$(mktemp)"
trap 'rm -rf "$LOCAL_SCHEMAS"; rm -f "$root"' EXIT
"$ROOT/tools/generate-manifests.sh" "$root" >/dev/null
validate "$SCHEMAS/index.json" "$root"

if ! diff \
  <(manifest_files "$ROOT" | cut -f1) \
  <(jq -r '.files[].path | select(startswith("schemas/") | not)' "$root" | LC_ALL=C sort) >&2
then
  echo "generated index does not match data/manifests" >&2
  failed=1
fi

if [ "$failed" -ne 0 ]; then
  echo "manifest validation failed" >&2
  exit 1
fi

echo "manifests validated"
