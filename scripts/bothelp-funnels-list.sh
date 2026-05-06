#!/usr/bin/env bash
# GET /v1/funnels — список активных авторассылок (funnels) кабинета.
# Флаги: --json (raw), --full (без обрезки)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_common.sh"

bothelp_load_config
out="$(bothelp_request GET /v1/funnels)"
bothelp_render "$out" "$@"
