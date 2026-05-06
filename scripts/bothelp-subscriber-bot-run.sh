#!/usr/bin/env bash
# POST /v1/subscribers/{id}/bot — запустить бота для подписчика с конкретного шага.
# Body (из OpenAPI спеки): {"botReferral":"...", "stepReferral":"..."}.
# Использование:
#   bothelp-subscriber-bot-run.sh <subscriber_id> <bot_referral> [<step_referral>]
#   bothelp-subscriber-bot-run.sh 123 c1723106923821 1723638253735 --by-cuid

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_common.sh"

[[ $# -ge 2 ]] || { echo "usage: $0 <subscriber_id> <bot_referral> [<step_referral>] [--by-cuid|--by-messenger]"; exit 1; }

sub_id="$1"; shift
bot_ref="$1"; shift
step_ref=""
id_kind="id"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --by-cuid) id_kind="cuid"; shift ;;
    --by-messenger) id_kind="messenger"; shift ;;
    *) if [[ -z "$step_ref" ]]; then step_ref="$1"; shift; else echo "unknown: $1" >&2; exit 1; fi ;;
  esac
done

case "$id_kind" in
  id)        path="/v1/subscribers/$sub_id/bot" ;;
  cuid)      path="/v1/subscribers/cuid/$sub_id/bot" ;;
  messenger) path="/v2/subscribers/messenger/$sub_id/bot" ;;
esac

body="$(python3 -c "
import json
d = {'botReferral': '$bot_ref'}
if '$step_ref': d['stepReferral'] = '$step_ref'
print(json.dumps(d, ensure_ascii=False))
")"

bothelp_load_config
echo "▶ POST $path  body=$body" >&2
out="$(bothelp_request POST "$path" "$body" "application/json")"
bothelp_render "$out" --full
