#!/usr/bin/env bash
# GET /v1/bots/{bot_referral}/steps — структура шагов одного бота.
# Использование: bothelp-bot-steps.sh <bot_referral> [--json|--full]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_common.sh"

[[ $# -ge 1 ]] || { echo "usage: $0 <bot_referral> [--json|--full]"; exit 1; }
ref="$1"; shift

bothelp_load_config
out="$(bothelp_request GET "/v1/bots/$ref/steps")"
bothelp_render "$out" "$@"
