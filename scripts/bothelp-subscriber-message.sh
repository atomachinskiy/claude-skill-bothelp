#!/usr/bin/env bash
# POST /v1/subscribers/{id}/messages — отправить индивидуальное сообщение.
# Content-Type: application/vnd.api+json (BotHelp требует именно его).
# Schema body не размечена; стандартный JSON:API формат:
#   {"data": {"type": "message", "attributes": {"text": "Hello"}}}
# Использование:
#   bothelp-subscriber-message.sh <id> --text "Привет, как дела?"
#   bothelp-subscriber-message.sh <id> --json '{"data":{"type":"message","attributes":{"text":"..."}}}'

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_common.sh"

[[ $# -ge 1 ]] || { echo "usage: $0 <id> [--by-cuid] (--text TXT | --json BODY)"; exit 1; }

sub_id="$1"; shift
id_kind="id"
text=""
body=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --by-cuid) id_kind="cuid"; shift ;;
    --text)    text="$2"; shift 2 ;;
    --json)    body="$2"; shift 2 ;;
    *) echo "unknown flag: $1" >&2; exit 1 ;;
  esac
done

case "$id_kind" in
  id)   path="/v1/subscribers/$sub_id/messages" ;;
  cuid) path="/v1/subscribers/cuid/$sub_id/messages" ;;
esac

if [[ -z "$body" && -n "$text" ]]; then
  body="$(python3 -c "
import json
print(json.dumps({'data': {'type': 'message', 'attributes': {'text': '''$text'''}}}, ensure_ascii=False))
")"
fi

[[ -n "$body" ]] || { echo "❌ Передай --text или --json" >&2; exit 1; }

bothelp_load_config
echo "▶ POST $path  body=$body" >&2
out="$(bothelp_request POST "$path" "$body" "application/vnd.api+json")"
bothelp_render "$out" --full
