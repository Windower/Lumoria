#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

ROOT="$(repo_root)"
if [ -f "$ROOT/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT/.env"
  set +a
fi

VERSION="$(meson_option "$ROOT" manifest_format_version)"
STAGE="$ROOT/dist/manifests/$VERSION"
ENDPOINT="${R2_ENDPOINT:-}"
BUCKET="${R2_BUCKET:-manifests}"

if [ -z "${R2_ACCESS_KEY_ID:-}" ] || [ -z "${R2_SECRET_ACCESS_KEY:-}" ] || [ -z "$ENDPOINT" ]; then
  echo "R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, and R2_ENDPOINT must be set in .env" >&2
  exit 1
fi

if ! command -v aws >/dev/null; then
  echo "aws CLI is required" >&2
  exit 1
fi

"$ROOT/tools/validate-manifests.sh"
"$ROOT/tools/generate-manifests.sh" "$STAGE/manifest.json" >/dev/null

while IFS=$'\t' read -r rel abs; do
  mkdir -p "$STAGE/$(dirname "$rel")"
  cp -a "$abs" "$STAGE/$rel"
done < <(manifest_files "$ROOT")

mkdir -p "$STAGE/schemas"
find "$ROOT/data/schemas" -maxdepth 1 -type f -name '*.json' -exec cp -a {} "$STAGE/schemas/" \;

dest="s3://$BUCKET/$VERSION"
export AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-auto}"

aws s3 sync "$STAGE" "$dest" \
  --endpoint-url "$ENDPOINT" \
  --exclude "manifest.json" \
  --delete \
  --cache-control "public, max-age=60" \
  --content-type "application/json"

aws s3 cp "$STAGE/manifest.json" "$dest/manifest.json" \
  --endpoint-url "$ENDPOINT" \
  --cache-control "no-cache, no-store, must-revalidate" \
  --content-type "application/json"

echo "$dest"
