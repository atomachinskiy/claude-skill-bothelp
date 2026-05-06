#!/usr/bin/env bash
# POST /v1/subscribers/{id}/funnel — добавить подписчика в авторассылку (funnel).
# Body schema не размечен — пробуем {"funnelReferral":"..."}.
# Использование:
#   bothelp-subscriber-funnel-add.sh <subscriber_id> <funnel_referral> [--by-cuid|--by-messenger]
#   bothelp-subscriber-funnel-add.sh <subscriber_id> --json '{"funnelReferral":"..."}'

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_common.sh"

[[ $# -ge 1 ]] || { echo "usage: $0 <subscriber_id> [<funnel_referral>] [--by-cuid|--by-messenger] [--json BODY]"; exit 1; }

sub_id="$1"; shift
funnel_ref=""
id_kind="id"
body=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --by-cuid)      id_kind="cuid"; shift ;;
    --by-messenger) id_kind="messenger"; shift ;;
    --json)         body="$2"; shift 2 ;;
    *) if [[ -z "$funnel_ref" ]]; then funnel_ref="$1"; shift; else echo "unknown: $1" >&2; exit 1; fi ;;
  esac
done

case "$id_kind" in
  id)        path="/v1/subscribers/$sub_id/funnel" ;;
  cuid)      path="/v1/subscribers/cuid/$sub_id/funnel" ;;
  messenger) path="/v2/subscribers/messenger/$sub_id/funnel" ;;
esac

if [[ -z "$body" && -n "$funnel_ref" ]]; then
  body="{\"funnelReferral\":\"$funnel_ref\"}"
fi
[[ -n "$body" ]] || { echo "❌ Передай <funnel_referral> или --json" >&2; exit 1; }

bothelp_load_config
echo "▶ POST $path  body=$body" >&2
out="$(bothelp_request POST "$path" "$body" "application/json")"
bothelp_render "$out" --full
