#!/usr/bin/env bash
# BotHelp common utilities — auto-refresh OAuth token, throttling, JSON helpers.
# Sourced by every bothelp-*.sh script.

set -euo pipefail

SKILL_DIR="${SKILL_DIR:-$HOME/.claude/skills/bothelp}"
ENV_FILE="$SKILL_DIR/config/.env"
SECRETS_FILE="$HOME/.claude/secrets/bothelp-app.json"

# rate-limit cushion: 10 req/sec hard cap → 100ms + jitter
THROTTLE_MS="${BOTHELP_THROTTLE_MS:-120}"

bothelp_die() {
  echo "❌ $*" >&2
  exit 1
}

bothelp_have() { command -v "$1" >/dev/null 2>&1; }

bothelp_check_deps() {
  for dep in jq curl python3; do
    bothelp_have "$dep" || bothelp_die "Не найден '$dep'. Установи: brew install $dep (macOS) или apt-get install $dep (Linux)."
  done
}

bothelp_load_config() {
  [[ -f "$ENV_FILE" ]] || bothelp_die "Нет $ENV_FILE — запусти мастер: bash $SKILL_DIR/scripts/bothelp-oauth-setup.sh"
  [[ -f "$SECRETS_FILE" ]] || bothelp_die "Нет $SECRETS_FILE — запусти мастер: bash $SKILL_DIR/scripts/bothelp-oauth-setup.sh"

  # shellcheck disable=SC1090
  set -a; source "$ENV_FILE"; set +a

  BOTHELP_CLIENT_ID="$(jq -r '.client_id' "$SECRETS_FILE")"
  BOTHELP_CLIENT_SECRET="$(jq -r '.client_secret' "$SECRETS_FILE")"
  : "${BOTHELP_API_BASE:=https://api.bothelp.io}"
  : "${BOTHELP_OAUTH_BASE:=https://oauth.bothelp.io}"
  : "${BOTHELP_TOKEN_EXPIRES_AT:=0}"
  : "${BOTHELP_ACCESS_TOKEN:=}"

  [[ -n "$BOTHELP_CLIENT_ID" && "$BOTHELP_CLIENT_ID" != "null" ]] || bothelp_die "client_id пустой — перезапусти мастер."
  [[ -n "$BOTHELP_CLIENT_SECRET" && "$BOTHELP_CLIENT_SECRET" != "null" ]] || bothelp_die "client_secret пустой — перезапусти мастер."
}

bothelp_refresh_token() {
  local resp http_code body
  resp="$(curl -sS -w '\n%{http_code}' -X POST "$BOTHELP_OAUTH_BASE/oauth2/token" \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    -d "grant_type=client_credentials&client_id=$BOTHELP_CLIENT_ID&client_secret=$BOTHELP_CLIENT_SECRET")"
  http_code="$(printf '%s' "$resp" | tail -n1)"
  body="$(printf '%s' "$resp" | sed '$d')"
  if [[ "$http_code" != "200" ]]; then
    bothelp_die "Не удалось получить токен (HTTP $http_code): $body"
  fi
  local token expires_in expires_at
  token="$(printf '%s' "$body" | jq -r '.access_token // empty')"
  expires_in="$(printf '%s' "$body" | jq -r '.expires_in // 3600')"
  [[ -n "$token" ]] || bothelp_die "В ответе нет access_token: $body"
  expires_at="$(python3 -c "import time; print(int(time.time()) + int('$expires_in'))")"

  python3 - "$ENV_FILE" "$token" "$expires_at" <<'PY'
import sys, pathlib
env_path, token, exp = sys.argv[1:]
p = pathlib.Path(env_path)
lines = p.read_text().splitlines() if p.exists() else []
out, seen_token, seen_exp = [], False, False
for ln in lines:
    if ln.startswith("BOTHELP_ACCESS_TOKEN="):
        out.append(f"BOTHELP_ACCESS_TOKEN={token}"); seen_token = True
    elif ln.startswith("BOTHELP_TOKEN_EXPIRES_AT="):
        out.append(f"BOTHELP_TOKEN_EXPIRES_AT={exp}"); seen_exp = True
    else:
        out.append(ln)
if not seen_token: out.append(f"BOTHELP_ACCESS_TOKEN={token}")
if not seen_exp:   out.append(f"BOTHELP_TOKEN_EXPIRES_AT={exp}")
p.write_text("\n".join(out) + "\n")
PY
  chmod 600 "$ENV_FILE"
  BOTHELP_ACCESS_TOKEN="$token"
  BOTHELP_TOKEN_EXPIRES_AT="$expires_at"
  echo "🔄 Токен обновлён (живёт до $(python3 -c "import time; print(time.strftime('%H:%M:%S', time.localtime($expires_at)))"))" >&2
}

bothelp_ensure_token() {
  local now buffer
  now="$(date +%s)"
  buffer=60  # обновляем за минуту до истечения
  if [[ -z "${BOTHELP_ACCESS_TOKEN:-}" || "$now" -ge "$((BOTHELP_TOKEN_EXPIRES_AT - buffer))" ]]; then
    bothelp_refresh_token
  fi
}

bothelp_throttle() {
  python3 -c "import time; time.sleep($THROTTLE_MS/1000)"
}

# bothelp_request <METHOD> <path-after-base> [body-json] [content-type]
# Возвращает body в stdout. Падает на не-2xx с понятным сообщением.
bothelp_request() {
  local method="$1"; shift
  local path="$1"; shift
  local body="${1:-}"
  local ctype="${2:-application/json}"

  bothelp_ensure_token
  bothelp_throttle

  # BotHelp у разных endpoints требует разное наличие/отсутствие trailing slash.
  # Используем -L --post301 --post302 --post303 чтобы curl сохранял body
  # при редиректах 30X. Без --postN curl на 307/POST превращается в GET и теряет body.
  local url="$BOTHELP_API_BASE$path"
  local args=(-sS -L --post301 --post302 --post303 -w '\n%{http_code}' -X "$method" "$url"
              -H "Authorization: Bearer $BOTHELP_ACCESS_TOKEN"
              -H "Accept: application/json")
  if [[ -n "$body" ]]; then
    args+=(-H "Content-Type: $ctype" -d "$body")
  fi

  local resp http_code response_body
  resp="$(curl "${args[@]}")"
  http_code="$(printf '%s' "$resp" | tail -n1)"
  response_body="$(printf '%s' "$resp" | sed '$d')"

  if [[ "$http_code" =~ ^2 ]]; then
    printf '%s' "$response_body"
    return 0
  fi

  # 401 → токен мог стухнуть из-за clock skew, попробуем один раз обновить и повторить
  if [[ "$http_code" == "401" ]]; then
    echo "⚠️  HTTP 401 — обновляю токен и повторяю запрос…" >&2
    bothelp_refresh_token
    # после добавления -L индекс header сместился; пересобираем по индексу-имени
    local i
    for i in "${!args[@]}"; do
      if [[ "${args[$i]}" == Authorization:* ]]; then
        args[$i]="Authorization: Bearer $BOTHELP_ACCESS_TOKEN"
        break
      fi
    done
    resp="$(curl "${args[@]}")"
    http_code="$(printf '%s' "$resp" | tail -n1)"
    response_body="$(printf '%s' "$resp" | sed '$d')"
    if [[ "$http_code" =~ ^2 ]]; then
      printf '%s' "$response_body"
      return 0
    fi
  fi

  echo "❌ HTTP $http_code: $method $path" >&2
  echo "   body: $response_body" >&2
  return 1
}

# Pretty-print JSON: by default first 30 lines, full с --full, raw с --json
bothelp_render() {
  local raw="$1"; shift
  local mode="pretty"
  for arg in "$@"; do
    case "$arg" in
      --json) mode="json" ;;
      --full) mode="full" ;;
    esac
  done
  case "$mode" in
    json) printf '%s\n' "$raw" ;;
    full) printf '%s\n' "$raw" | jq . ;;
    *)    printf '%s\n' "$raw" | jq . | head -30 ;;
  esac
}

bothelp_check_deps
