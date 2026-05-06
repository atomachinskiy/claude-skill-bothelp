#!/usr/bin/env bash
# Универсальный raw-вызов любого эндпоинта BotHelp.
# Использование:
#   bothelp-call.sh GET  /v1/bots
#   bothelp-call.sh GET  '/v1/subscribers?email=test@example.com'
#   bothelp-call.sh POST /v1/subscribers/123/bot '{"botReferral":"abc"}'
#   bothelp-call.sh PATCH /v1/subscribers/123/customFields '{"data":{"x":"y"}}' application/json
#
# Флаги: --json (raw), --full (без обрезки 30 строк); по умолчанию pretty-30-lines.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_common.sh"

[[ $# -ge 2 ]] || { echo "usage: $0 <METHOD> <PATH> [BODY-JSON] [CONTENT-TYPE] [--json|--full]"; exit 1; }

method="$1"; path="$2"; body=""; ctype="application/json"
shift 2
flags=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json|--full) flags+=("$1") ;;
    *) if [[ -z "$body" ]]; then body="$1"; else ctype="$1"; fi ;;
  esac
  shift
done

bothelp_load_config
out="$(bothelp_request "$method" "$path" "$body" "$ctype")"
bothelp_render "$out" "${flags[@]+"${flags[@]}"}"
