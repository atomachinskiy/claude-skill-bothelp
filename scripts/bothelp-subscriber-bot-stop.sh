#!/usr/bin/env bash
# DELETE /v1/subscribers/{id}/bot — остановить бота для подписчика.
# !! BotHelp DELETE требует body с botReferral (а не пустой DELETE как обычно в REST).
# Использование: bothelp-subscriber-bot-stop.sh <id> <bot_referral> [--by-cuid|--by-messenger]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_common.sh"

[[ $# -ge 2 ]] || { echo "usage: $0 <id> <bot_referral> [--by-cuid|--by-messenger]"; exit 1; }
sub_id="$1"; shift
bot_ref="$1"; shift
id_kind="id"
case "${1:-}" in
  --by-cuid) id_kind="cuid" ;;
  --by-messenger) id_kind="messenger" ;;
esac

case "$id_kind" in
  id)        path="/v1/subscribers/$sub_id/bot" ;;
  cuid)      path="/v1/subscribers/cuid/$sub_id/bot" ;;
  messenger) path="/v2/subscribers/messenger/$sub_id/bot" ;;
esac

body="{\"botReferral\":\"$bot_ref\"}"
bothelp_load_config
echo "▶ DELETE $path  body=$body" >&2
out="$(bothelp_request DELETE "$path" "$body" "application/json")"
bothelp_render "$out" --full
