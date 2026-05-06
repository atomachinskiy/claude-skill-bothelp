#!/usr/bin/env bash
# GET /v1/subscribers — экспорт подписчиков с фильтрами.
# Флаги:
#   --since <YYYY-MM-DD>  → createdAtAfter (timestamp)
#   --after <id>          → курсор пагинации (subscriber shift by ID)
#   --email <email>
#   --phone <phone>
#   --json | --full

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_common.sh"

since=""
after=""
email=""
phone=""
flags=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --since) since="$2"; shift 2 ;;
    --after) after="$2"; shift 2 ;;
    --email) email="$2"; shift 2 ;;
    --phone) phone="$2"; shift 2 ;;
    --json|--full) flags+=("$1"); shift ;;
    *) echo "unknown flag: $1" >&2; exit 1 ;;
  esac
done

query=""
join() { if [[ -n "$query" ]]; then query="$query&"; fi; }

if [[ -n "$since" ]]; then
  ts="$(python3 -c "import datetime,time; print(int(time.mktime(datetime.date.fromisoformat('$since').timetuple())))")"
  join; query="${query}createdAtAfter=$ts"
fi
if [[ -n "$after" ]]; then join; query="${query}after=$after"; fi
if [[ -n "$email" ]]; then join; query="${query}email=$email"; fi
if [[ -n "$phone" ]]; then join; query="${query}phone=$phone"; fi

path="/v1/subscribers"
[[ -n "$query" ]] && path="$path?$query"

bothelp_load_config
out="$(bothelp_request GET "$path")"
bothelp_render "$out" "${flags[@]+"${flags[@]}"}"
