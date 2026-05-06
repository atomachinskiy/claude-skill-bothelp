#!/usr/bin/env bash
# GET /v1/bots — карта всех активных ботов кабинета.
# Флаги: --json (raw), --full (без обрезки), --table (таблица: referral, name)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_common.sh"

mode="default"
flags=()
for arg in "$@"; do
  case "$arg" in
    --table) mode="table" ;;
    --json|--full) flags+=("$arg") ;;
  esac
done

bothelp_load_config
out="$(bothelp_request GET /v1/bots)"

if [[ "$mode" == "table" ]]; then
  printf '%s' "$out" | jq -r '
    (if type == "array" then . else (.data? // [.]) end)
    | .[]
    | [(.referral // .id // "?"), (.title // .name // "?")]
    | @tsv' | column -t -s $'\t'
else
  bothelp_render "$out" "${flags[@]+"${flags[@]}"}"
fi
