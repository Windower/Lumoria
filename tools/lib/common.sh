#!/usr/bin/env bash
set -euo pipefail

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

repo_root() {
  cd "$_LIB_DIR/../.." && pwd
}

meson_option() {
  local root="$1" name="$2"
  awk -v name="$name" '
    $0 ~ name { hit = 1 }
    hit && /value:/ {
      if (match($0, /'\''[^'\'']+'\''/)) {
        print substr($0, RSTART + 1, RLENGTH - 2)
        exit
      }
      gsub(/[^0-9]/, "", $0)
      print
      exit
    }
  ' "$root/meson_options.txt"
}

# Every manifest under data/manifests as "rel<TAB>abs": top-level files plus one level of kind directories.
manifest_files() {
  find "$1/data/manifests" -mindepth 1 -maxdepth 2 -type f -name '*.json' -printf '%P\t%p\n' | LC_ALL=C sort
}

# Schema file for a manifest path, the same rule ManifestStore.schema_kind_for_path applies at runtime:
# kind/name.json validates against the singular kind, name.json against its own name.
schema_for() {
  local rel="$1" kind="${1%%/*}"
  if [ "$kind" = "$rel" ]; then
    printf '%s\n' "$rel"
  else
    printf '%s.json\n' "${kind%s}"
  fi
}
