#!/usr/bin/env bash
set -euo pipefail

manifest="$1"
target_dir="$2"
output="$3"

args=(
  build
  --manifest-path "$manifest"
  --target-dir "$target_dir"
  --release
  --locked
)
if [[ "${CARGO_NET_OFFLINE:-}" == "true" ]]; then
  args+=(--offline)
fi

cargo "${args[@]}"
cp "$target_dir/release/liblumoria_native.a" "$output"
