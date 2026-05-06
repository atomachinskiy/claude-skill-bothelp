#!/usr/bin/env bash
# PATCH /v1/subscribers/{id} — обновить общие поля подписчика.
#
# !! BotHelp использует JSON Patch (RFC 6902): body — массив операций
#    [{"op":"replace|add|remove","path":"/field","value":...}].
# Спека OpenAPI это не указывает; узнаём из VALIDATION_ERROR ответа.
#
# Использование:
#   bothelp-subscriber-update.sh <id> --tags-add молчун
#   bothelp-subscriber-update.sh <id> --tags-remove новичок
#   bothelp-subscriber-update.sh <id> --tags-set "tag1,tag2,tag3"
#   bothelp-subscriber-update.sh <id> --name "Новое имя"
#   bothelp-subscriber-update.sh <id> --email new@example.com
#   bothelp-subscriber-update.sh <id> --phone 79991234567
#   bothelp-subscriber-update.sh <id> --json '[{"op":"replace","path":"/tags","value":[]}]'

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_common.sh"

[[ $# -ge 1 ]] || { echo "usage: $0 <id> [--by-cuid|--by-messenger] (--tags-add|--tags-remove|--tags-set|--name|--email|--phone|--json) ..."; exit 1; }

sub_id="$1"; shift
id_kind="id"
patch_json=""
tag_add=""
tag_remove=""
tag_set=""
new_name=""
new_email=""
new_phone=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --by-cuid)      id_kind="cuid"; shift ;;
    --by-messenger) id_kind="messenger"; shift ;;
    --json)         patch_json="$2"; shift 2 ;;
    --tags-add)     tag_add="$2"; shift 2 ;;
    --tags-remove)  tag_remove="$2"; shift 2 ;;
    --tags-set)     tag_set="$2"; shift 2 ;;
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
  # Соберём массив operations через jq — он надёжно экранирует unicode.
  ops_json='[]'

  add_field_op() {
    local field="$1" value="$2"
    [[ -z "$value" ]] && return
    ops_json="$(jq -c --arg p "/$field" --arg v "$value" '. + [{op:"replace", path:$p, value:$v}]' <<<"$ops_json")"
  }
  add_field_op name "$new_name"
  add_field_op email "$new_email"
  add_field_op phone "$new_phone"

  # Tags: add/remove требуют чтения текущего состояния, set — нет.
  if [[ -n "$tag_add" || -n "$tag_remove" ]]; then
    current="$(bothelp_request GET "/v1/subscribers" | jq -c --arg id "$sub_id" '.data[] | select((.id|tostring)==$id) | .tags // []')"
    [[ -n "$current" && "$current" != "null" ]] || bothelp_die "Подписчик id=$sub_id не найден"
    new_tags="$(jq -c --arg add "$tag_add" --arg rm "$tag_remove" '
      . as $cur
      | (if $add!="" and ($cur|index($add)|not) then $cur + [$add] else $cur end)
      | (if $rm !="" and (.|index($rm))         then . - [$rm]   else . end)
    ' <<<"$current")"
    ops_json="$(jq -c --argjson v "$new_tags" '. + [{op:"replace", path:"/tags", value:$v}]' <<<"$ops_json")"
  fi
  if [[ -n "$tag_set" ]]; then
    arr="$(jq -c -R 'split(",") | map(.|gsub("^\\s+|\\s+$";""))| map(select(.!=""))' <<<"$tag_set")"
    ops_json="$(jq -c --argjson v "$arr" '. + [{op:"replace", path:"/tags", value:$v}]' <<<"$ops_json")"
  fi

  count="$(jq 'length' <<<"$ops_json")"
  [[ "$count" -gt 0 ]] || { echo "❌ Нет операций. Используй --tags-add/--tags-remove/--tags-set/--name/--email/--phone/--json" >&2; exit 1; }
  patch_json="$ops_json"
fi

echo "▶ PATCH $path  body=$patch_json" >&2
out="$(bothelp_request PATCH "$path" "$patch_json" "application/json")"
if [[ -z "$out" ]]; then
  echo "✓ OK (пустой ответ)"
else
  bothelp_render "$out" --full
fi
