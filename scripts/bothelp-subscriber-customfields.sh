#!/usr/bin/env bash
# PATCH /v1/subscribers/{id}/customFields — обновить кастомные поля.
# Формат: JSON Patch RFC 6902 — массив операций [{op:"replace", path:"/<key>", value:"..."}].
# Подтверждено работающим: op:replace на любом /<key>.
#
# Использование:
#   bothelp-subscriber-customfields.sh <id> --set city=Москва --set status=vip
#   bothelp-subscriber-customfields.sh <id> --json '[{"op":"replace","path":"/city","value":"M"}]'

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_common.sh"

[[ $# -ge 1 ]] || { echo "usage: $0 <id> [--by-cuid|--by-messenger] (--json BODY | --set k=v ...)"; exit 1; }

sub_id="$1"; shift
id_kind="id"
patch_json=""
declare -a kvs=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --by-cuid)      id_kind="cuid"; shift ;;
    --by-messenger) id_kind="messenger"; shift ;;
    --json)         patch_json="$2"; shift 2 ;;
    --set)          kvs+=("$2"); shift 2 ;;
    *) echo "unknown flag: $1" >&2; exit 1 ;;
  esac
done

case "$id_kind" in
  id)        path="/v1/subscribers/$sub_id/customFields" ;;
  cuid)      path="/v1/subscribers/cuid/$sub_id/customFields" ;;
  messenger) path="/v2/subscribers/messenger/$sub_id/custom-fields" ;;
esac

if [[ -z "$patch_json" && ${#kvs[@]} -gt 0 ]]; then
  ops='[]'
  for kv in "${kvs[@]}"; do
    if [[ "$kv" == *=* ]]; then
      k="${kv%%=*}"; v="${kv#*=}"
      ops="$(jq -c --arg p "/$k" --arg v "$v" '. + [{op:"replace", path:$p, value:$v}]' <<<"$ops")"
    fi
  done
  patch_json="$ops"
fi

[[ -n "$patch_json" && "$patch_json" != "[]" ]] || { echo "❌ Передай --json или --set k=v" >&2; exit 1; }

bothelp_load_config
echo "▶ PATCH $path  body=$patch_json" >&2
out="$(bothelp_request PATCH "$path" "$patch_json" "application/json")"
[[ -z "$out" ]] && echo "✓ OK" || bothelp_render "$out" --full
