#!/usr/bin/env bash
# DELETE /v1/subscribers/{id}/funnel — убрать подписчика из авторассылки.
# !! Требует body с funnelReferral (нестандартное поведение DELETE).
# Использование: bothelp-subscriber-funnel-remove.sh <id> <funnel_referral> [--by-cuid|--by-messenger]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_common.sh"

[[ $# -ge 2 ]] || { echo "usage: $0 <id> <funnel_referral> [--by-cuid|--by-messenger]"; exit 1; }
sub_id="$1"; shift
funnel_ref="$1"; shift
id_kind="id"
case "${1:-}" in
  --by-cuid) id_kind="cuid" ;;
  --by-messenger) id_kind="messenger" ;;
esac

case "$id_kind" in
  id)        path="/v1/subscribers/$sub_id/funnel" ;;
  cuid)      path="/v1/subscribers/cuid/$sub_id/funnel" ;;
  messenger) path="/v2/subscribers/messenger/$sub_id/funnel" ;;
esac

body="{\"funnelReferral\":\"$funnel_ref\"}"
bothelp_load_config
echo "▶ DELETE $path  body=$body" >&2
out="$(bothelp_request DELETE "$path" "$body" "application/json")"
bothelp_render "$out" --full
