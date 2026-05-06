#!/usr/bin/env bash
# PATCH /v1/subscribers/{id}/customFields — обновить кастомные поля подписчика.
# Точная схема body не размечена в OpenAPI; пробуем стандартный {key: value}.
# Использование:
#   bothelp-subscriber-customfields.sh <id> --json '{"key":"value"}'
#   bothelp-subscriber-customfields.sh <id> --set city=Москва --set status=vip

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_common.sh"

[[ $# -ge 1 ]] || { echo "usage: $0 <id> [--by-cuid|--by-messenger] (--json BODY | --set k=v ...)"; exit 1; }

sub_id="$1"; shift
id_kind="id"
body=""
declare -a kvs=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --by-cuid)      id_kind="cuid"; shift ;;
    --by-messenger) id_kind="messenger"; shift ;;
    --json)         body="$2"; shift 2 ;;
    --set)          kvs+=("$2"); shift 2 ;;
    *) echo "unknown flag: $1" >&2; exit 1 ;;
  esac
done

case "$id_kind" in
  id)        path="/v1/subscribers/$sub_id/customFields" ;;
  cuid)      path="/v1/subscribers/cuid/$sub_id/customFields" ;;
  messenger) path="/v2/subscribers/messenger/$sub_id/custom-fields" ;;
esac

if [[ -z "$body" && ${#kvs[@]} -gt 0 ]]; then
  body="$(python3 -c "
import json, sys
d = {}
for kv in [$(printf '%s\n' "${kvs[@]}" | python3 -c "import sys,json; print(','.join(json.dumps(l.strip()) for l in sys.stdin if l.strip()))")]:
    if '=' in kv: k,v = kv.split('=',1); d[k]=v
print(json.dumps(d, ensure_ascii=False))
")"
fi

[[ -n "$body" && "$body" != "{}" ]] || { echo "❌ Передай --json или --set k=v" >&2; exit 1; }

bothelp_load_config
echo "▶ PATCH $path  body=$body" >&2
out="$(bothelp_request PATCH "$path" "$body" "application/json")"
bothelp_render "$out" --full
