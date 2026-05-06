#!/usr/bin/env bash
# BotHelp OAuth setup wizard — собирает client_id + client_secret интерактивно,
# меняет на access_token через grant_type=client_credentials, сохраняет конфиг.
#
# Cross-platform: macOS / Linux / WSL / Git Bash на Windows. Браузер не нужен —
# в client_credentials flow нет user-consent редиректа.
#
# Запускается ПОЛЬЗОВАТЕЛЕМ В ЕГО СОБСТВЕННОМ ТЕРМИНАЛЕ. client_secret вводится
# через `read -s` (скрытый ввод) и не появляется в чате с ботом.

set -euo pipefail

SKILL_DIR="$HOME/.claude/skills/bothelp"
SECRETS_DIR="$HOME/.claude/secrets"
SECRETS_FILE="$SECRETS_DIR/bothelp-app.json"
ENV_FILE="$SKILL_DIR/config/.env"
ENV_EXAMPLE="$SKILL_DIR/config/.env.example"

OAUTH_BASE="https://oauth.bothelp.io"
API_BASE="https://api.bothelp.io"

CYAN=$'\033[0;36m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'; RED=$'\033[0;31m'; RST=$'\033[0m'

step()  { echo "${CYAN}▶ $*${RST}"; }
ok()    { echo "${GREEN}✓ $*${RST}"; }
warn()  { echo "${YELLOW}⚠ $*${RST}"; }
die()   { echo "${RED}✗ $*${RST}" >&2; exit 1; }

[[ -d "$SKILL_DIR" ]] || die "$SKILL_DIR не существует. Сначала установи скилл (git clone … ~/.claude/skills/bothelp)."

step "Проверяю зависимости (jq, curl, python3)…"
for dep in jq curl python3; do
  command -v "$dep" >/dev/null 2>&1 || die "Не найден '$dep'. macOS: brew install $dep | Linux: apt-get install $dep | Windows (Git Bash): установи через chocolatey."
done
ok "Зависимости на месте"

mkdir -p "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR" 2>/dev/null || true

if [[ -f "$SECRETS_FILE" ]]; then
  warn "Найден существующий $SECRETS_FILE"
  read -r -p "Перезаписать credentials? (y/N): " yn
  yn_lower="$(printf '%s' "$yn" | tr '[:upper:]' '[:lower:]')"
  [[ "$yn_lower" == "y" || "$yn_lower" == "yes" ]] || die "Отменено пользователем."
fi

cat <<EOF

${CYAN}=== Шаг 1: создать OAuth-приложение в BotHelp ===${RST}

  1. Открой кабинет BotHelp: https://app.bothelp.io
  2. Перейди в раздел: Настройки → Разработчикам → API → Создать приложение
     (точное расположение может отличаться, ищи раздел про OAuth-приложения)
  3. Тип авторизации: ${YELLOW}OAuth 2.0 / API integration / Server-to-server${RST}
  4. Скопируй ${YELLOW}client_id${RST} и ${YELLOW}client_secret${RST}, они нужны на шаге 2

  ${CYAN}redirect_uri и user-consent НЕ требуются${RST} — у BotHelp client_credentials flow,
  это машина-машина, без браузерной авторизации.

EOF

read -r -p "Готов? Жми Enter, чтобы перейти к шагу 2…"

echo
step "Шаг 2: ввод client_id и client_secret"
echo "  client_id — публичный, можно вставить как обычно"
echo "  client_secret — будет скрыт при вводе (read -s)"
echo

read -r -p "client_id: " CLIENT_ID
[[ -n "$CLIENT_ID" ]] || die "client_id пустой"

read -r -s -p "client_secret (ввод скрыт): " CLIENT_SECRET
echo
[[ -n "$CLIENT_SECRET" ]] || die "client_secret пустой"

# Сохраняем secrets ПЕРЕД обменом — чтобы при сбое можно было повторить без переввода
umask 077
cat > "$SECRETS_FILE" <<JSON
{
  "client_id": "$CLIENT_ID",
  "client_secret": "$CLIENT_SECRET",
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
chmod 600 "$SECRETS_FILE"
ok "Сохранил $SECRETS_FILE (chmod 600)"

echo
step "Шаг 3: обмениваю credentials на access_token (POST /oauth2/token)…"
RESP="$(curl -sS -w '\n%{http_code}' -X POST "$OAUTH_BASE/oauth2/token" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d "grant_type=client_credentials&client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET")"
HTTP_CODE="$(printf '%s' "$RESP" | tail -n1)"
BODY="$(printf '%s' "$RESP" | sed '$d')"

if [[ "$HTTP_CODE" != "200" ]]; then
  echo
  warn "BotHelp ответил HTTP $HTTP_CODE:"
  printf '%s\n' "$BODY"
  cat <<EOF

${YELLOW}Что проверить:${RST}
  • client_id и client_secret скопированы без лишних пробелов
  • OAuth-приложение в BotHelp активировано (не draft)
  • У приложения тип «client_credentials / API integration», а не «authorization_code»

EOF
  die "Не удалось получить токен. Перезапусти мастер с правильными credentials."
fi

ACCESS_TOKEN="$(printf '%s' "$BODY" | jq -r '.access_token // empty')"
EXPIRES_IN="$(printf '%s' "$BODY" | jq -r '.expires_in // 3600')"
TOKEN_TYPE="$(printf '%s' "$BODY" | jq -r '.token_type // "Bearer"')"
EXPIRES_AT="$(python3 -c "import time; print(int(time.time()) + int('$EXPIRES_IN'))")"

[[ -n "$ACCESS_TOKEN" ]] || die "В ответе нет access_token: $BODY"
ok "Получен access_token (живёт ${EXPIRES_IN}с)"

echo
step "Шаг 4: записываю $ENV_FILE (chmod 600)…"
if [[ ! -f "$ENV_FILE" && -f "$ENV_EXAMPLE" ]]; then
  cp "$ENV_EXAMPLE" "$ENV_FILE"
fi

python3 - "$ENV_FILE" "$ACCESS_TOKEN" "$EXPIRES_AT" "$TOKEN_TYPE" <<'PY'
import sys, pathlib
env_path, token, exp, ttype = sys.argv[1:]
p = pathlib.Path(env_path)
lines = p.read_text().splitlines() if p.exists() else []
data = {
    "BOTHELP_ACCESS_TOKEN": token,
    "BOTHELP_TOKEN_TYPE": ttype,
    "BOTHELP_TOKEN_EXPIRES_AT": exp,
    "BOTHELP_API_BASE": "https://api.bothelp.io",
    "BOTHELP_OAUTH_BASE": "https://oauth.bothelp.io",
}
out, seen = [], set()
for ln in lines:
    key = ln.split("=",1)[0] if "=" in ln else ln
    if key in data:
        out.append(f"{key}={data[key]}"); seen.add(key)
    else:
        out.append(ln)
for k, v in data.items():
    if k not in seen:
        out.append(f"{k}={v}")
p.write_text("\n".join(out) + "\n")
PY
chmod 600 "$ENV_FILE"
ok "Записал $ENV_FILE"

echo
step "Шаг 5: sanity-check — GET /v1/bots…"
SANITY="$(curl -sS -w '\n%{http_code}' \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H 'Accept: application/json' \
  "$API_BASE/v1/bots")"
SCODE="$(printf '%s' "$SANITY" | tail -n1)"
SBODY="$(printf '%s' "$SANITY" | sed '$d')"

if [[ "$SCODE" =~ ^2 ]]; then
  COUNT="$(printf '%s' "$SBODY" | jq 'if type=="array" then length elif .data? then (.data|length) else 0 end' 2>/dev/null || echo "?")"
  ok "BotHelp отвечает (HTTP $SCODE). Активных ботов: $COUNT"
else
  warn "Sanity-check вернул HTTP $SCODE: $SBODY"
  warn "Скилл всё равно сохранил конфиг — попробуй вручную: bash $SKILL_DIR/scripts/bothelp-bots-list.sh"
fi

cat <<EOF

${GREEN}=== Готово! ===${RST}

  Конфиг:           $ENV_FILE
  Credentials:      $SECRETS_FILE
  Auto-refresh:     встроен в _common.sh (за 60с до истечения токена)

Попробуй:
  bash $SKILL_DIR/scripts/bothelp-bots-list.sh
  bash $SKILL_DIR/scripts/bothelp-funnels-list.sh

Если что-то сломается — расскажи AI-ассистенту вывод stderr, он подскажет.
EOF
