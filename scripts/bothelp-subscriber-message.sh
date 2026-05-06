#!/usr/bin/env bash
# POST /v1/subscribers/{id}/messages — отправить индивидуальное сообщение.
# Content-Type: application/vnd.api+json (BotHelp требует именно его).
#
# !! Схема разгадана 2026-05-06 экспериментально (в OpenAPI спеке тело не размечено):
#   Body: {"data": {"content": [<message-block>, ...]}}
#   <message-block> может быть:
#     - "строка"                           — простой текст
#     - {"type":"text","text":"..."}       — текст с явным типом
#     - {"type":"image","url":"https://"}  — картинка
#     - {"message":"..."}                  — альтернативный текстовый блок
#   Кнопки (`type:button`) и другие сложные блоки — структура не проверена.
#
# Использование:
#   bothelp-subscriber-message.sh <id> --text "Привет!"
#   bothelp-subscriber-message.sh <id> --text "Hi" --text "Hi again"     # несколько блоков
#   bothelp-subscriber-message.sh <id> --image https://example.com/x.jpg
#   bothelp-subscriber-message.sh <id> --json '{"data":{"content":[...]}}'

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_common.sh"

[[ $# -ge 1 ]] || { echo "usage: $0 <id> [--by-cuid] (--text TXT [--text TXT ...] | --image URL | --json BODY)"; exit 1; }

sub_id="$1"; shift
id_kind="id"
patch_json=""
declare -a texts=()
declare -a images=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --by-cuid) id_kind="cuid"; shift ;;
    --text)    texts+=("$2"); shift 2 ;;
    --image)   images+=("$2"); shift 2 ;;
    --json)    patch_json="$2"; shift 2 ;;
    *) echo "unknown flag: $1" >&2; exit 1 ;;
  esac
done

case "$id_kind" in
  id)   path="/v1/subscribers/$sub_id/messages" ;;
  cuid) path="/v1/subscribers/cuid/$sub_id/messages" ;;
esac

if [[ -z "$patch_json" ]]; then
  content='[]'
  for t in "${texts[@]+"${texts[@]}"}"; do
    content="$(jq -c --arg s "$t" '. + [$s]' <<<"$content")"
  done
  for u in "${images[@]+"${images[@]}"}"; do
    content="$(jq -c --arg u "$u" '. + [{type:"image", url:$u}]' <<<"$content")"
  done
  count="$(jq 'length' <<<"$content")"
  [[ "$count" -gt 0 ]] || { echo "❌ Передай --text или --image или --json" >&2; exit 1; }
  patch_json="$(jq -c --argjson c "$content" '{data:{content:$c}}' <<<'{}')"
fi

bothelp_load_config
echo "▶ POST $path  body=$patch_json" >&2
out="$(bothelp_request POST "$path" "$patch_json" "application/vnd.api+json")"
bothelp_render "$out" --full
