# BotHelp — пошаговая настройка скилла

## 🚀 Быстрый путь — мастер настройки

```bash
bash ~/.claude/skills/bothelp/scripts/bothelp-oauth-setup.sh
```

Мастер cross-platform (macOS / Linux / WSL / Git Bash на Windows). Спрашивает `client_id` (видимый ввод) и `client_secret` (скрытый, через `read -s`), сам обменивает их на access_token, сохраняет конфиг с `chmod 600`, делает sanity-check на `/v1/bots`. Браузер не нужен — это `client_credentials` flow, без user-consent редиректа.

## Ручной путь (fallback)

### 1. Создать OAuth-приложение в BotHelp

Открой кабинет BotHelp → `Настройки → Разработчикам → API → Создать приложение` (точное расположение раздела зависит от версии UI). Тип авторизации: **client_credentials / API integration / Server-to-server**. Скопируй `client_id` и `client_secret`.

### 2. Сохранить credentials

```bash
mkdir -p ~/.claude/secrets && chmod 700 ~/.claude/secrets
cat > ~/.claude/secrets/bothelp-app.json <<EOF
{"client_id":"YOUR_CLIENT_ID","client_secret":"YOUR_CLIENT_SECRET"}
EOF
chmod 600 ~/.claude/secrets/bothelp-app.json
```

### 3. Получить access_token

```bash
curl -s -X POST https://oauth.bothelp.io/oauth2/token \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d "grant_type=client_credentials&client_id=YOUR_ID&client_secret=YOUR_SECRET"
```

В ответе `{access_token, expires_in: 3600, token_type: "Bearer"}`.

### 4. Записать `.env`

```
BOTHELP_ACCESS_TOKEN=<token>
BOTHELP_TOKEN_TYPE=Bearer
BOTHELP_TOKEN_EXPIRES_AT=<epoch_now + 3600>
BOTHELP_API_BASE=https://api.bothelp.io
BOTHELP_OAUTH_BASE=https://oauth.bothelp.io
```

`chmod 600 ~/.claude/skills/bothelp/config/.env`.

### 5. Sanity-check

```bash
bash ~/.claude/skills/bothelp/scripts/bothelp-bots-list.sh --table
```

Должна вывести таблицу `referral → title` всех активных ботов кабинета.

## Troubleshooting

| Симптом | Что проверить |
|---|---|
| `HTTP 400` при обмене токена | `client_id`/`client_secret` без пробелов; OAuth-приложение в BotHelp активировано (не draft); тип приложения именно `client_credentials` |
| `HTTP 301 Moved Permanently` | Это норма для BotHelp — endpoints requiring trailing slash непоследовательно; `_common.sh` использует `curl -L` чтобы следовать редиректу |
| `HTTP 401` через час | Токен истёк, `_common.sh` обновит автоматически. Если не обновляется — проверь что `client_id`/`client_secret` в `~/.claude/secrets/bothelp-app.json` ещё валидны |
| `Patch instruction not recognized` на write | Это известная гоча тегов — см. SKILL.md, секция «⚠️ Теги подписчика». Для name/email/phone используй `op:replace path:/<field>` |

## Безопасность

- `.env` и `bothelp-app.json` — `chmod 600`, только владелец читает
- Не коммить эти файлы в git (репозиторий уже включает `.gitignore` для них)
- При утечке `client_secret` — пересоздай приложение в кабинете BotHelp, старое деактивируй
- Токен живёт час, поэтому даже при leak ущерб ограничен временем
