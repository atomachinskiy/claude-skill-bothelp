#!/usr/bin/env bash
# PATCH /v1/subscribers/{id} — обновить общие поля и теги подписчика.
#
# !! BotHelp использует JSON Patch RFC 6902, но с ограничениями по op-ам:
#   - Простые поля (name, email, phone): op:replace path:/<field> value:"..."
#   - Теги (массив): op:add path:/tags value:[...]  и  op:remove path:/tags value:[...]
#     ⚠️ op:replace на /tags возвращает «Patch instruction not recognized»
#
# Использование:
#   bothelp-subscriber-update.sh <id> --tags-add молчун
#   bothelp-subscriber-update.sh <id> --tags-add "молчун,re_engagement"  # сразу несколько
#   bothelp-subscriber-update.sh <id> --tags-remove новичок
#   bothelp-subscriber-update.sh <id> --name "Новое имя"
#   bothelp-subscriber-update.sh <id> --email new@example.com
#   bothelp-subscriber-update.sh <id> --json '[{"op":"add","path":"/tags","value":["x"]}]'

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_common.sh"

[[ $# -ge 1 ]] || { echo "usage: $0 <id> [--by-cuid|--by-messenger] (--tags-add T | --tags-remove T | --name N | --email E | --phone P | --json BODY) ..."; exit 1; }

sub_id="$1"; shift
id_kind="id"
patch_json=""
tags_add=""
tags_remove=""
new_name=""
new_email=""
new_phone=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --by-cuid)      id_kind="cuid"; shift ;;
    --by-messenger) id_kind="messenger"; shift ;;
    --json)         patch_json="$2"; shift 2 ;;
    --tags-add)     tags_add="$2"; shift 2 ;;
    --tags-remove)  tags_remove="$2"; shift 2 ;;
    --name)         new_name="$2"; shift 2 ;;
    --email)        new_email="$2"; shift 2 ;;
    --phone)        new_phone="$2"; shift 2 ;;
    *) echo "unknown flag: $1" >&2; exit 1 ;;
  esac
done

case "$id_kind" in
  id)        path="/v1/subscribers/$sub_id" ;;
  cuid)      path="/v1/subscribers/cuid/$sub_id" ;;
  messenger) path="/v2/subscribers/messenger/$sub_id" ;;
esac

bothelp_load_config

if [[ -z "$patch_json" ]]; then
  ops_json='[]'
  add_op() {
    ops_json="$(jq -c --argjson op "$1" '. + [$op]' <<<"$ops_json")"
  }

  # Простые поля — op:replace
  for fv in "name=$new_name" "email=$new_email" "phone=$new_phone"; do
    field="${fv%%=*}"; value="${fv#*=}"
    [[ -z "$value" ]] && continue
    op="$(jq -c -n --arg p "/$field" --arg v "$value" '{op:"replace", path:$p, value:$v}')"
    add_op "$op"
  done

  # Теги-добавить (поддерживает CSV: --tags-add "a,b,c")
  if [[ -n "$tags_add" ]]; then
    arr="$(jq -c -n -R --arg s "$tags_add" '$s | split(",") | map(.|gsub("^\\s+|\\s+$";"")) | map(select(.!=""))')"
    op="$(jq -c -n --argjson v "$arr" '{op:"add", path:"/tags", value:$v}')"
    add_op "$op"
  fi

  # Теги-удалить
  if [[ -n "$tags_remove" ]]; then
    arr="$(jq -c -n -R --arg s "$tags_remove" '$s | split(",") | map(.|gsub("^\\s+|\\s+$";"")) | map(select(.!=""))')"
    op="$(jq -c -n --argjson v "$arr" '{op:"remove", path:"/tags", value:$v}')"
    add_op "$op"
  fi

  count="$(jq 'length' <<<"$ops_json")"
  [[ "$count" -gt 0 ]] || { echo "❌ Нет операций. Используй --tags-add/--tags-remove/--name/--email/--phone/--json" >&2; exit 1; }
  patch_json="$ops_json"
fi

echo "▶ PATCH $path  body=$patch_json" >&2
out="$(bothelp_request PATCH "$path" "$patch_json" "application/json")"
if [[ -z "$out" ]]; then
  echo "✓ OK"
else
  bothelp_render "$out" --full
fi
