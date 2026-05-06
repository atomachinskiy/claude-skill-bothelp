# claude-skill-bothelp

Claude Code skill для работы с **BotHelp Open API** — мультимессенджерные чат-боты (Telegram, Instagram, VK, Facebook, WhatsApp). Превращает Claude в AI-аналитика, AI-сегментатора и AI-оператора над кабинетом BotHelp.

## Что умеет

**Аналитика (полностью работает):**
- Карта всех активных ботов (referral + title)
- Структура шагов любого бота
- Список авторассылок (funnels)
- Полный экспорт подписчиков с пагинацией и фильтрами (период, email, phone)
- Собственно из этих данных — drop-off по шагам, churn, UTM-источники, сегментация

**Управление (частично, JSON Patch RFC 6902):**
- Обновление имени, email, телефона подписчика — `op:replace path:/name`
- Запуск/остановка бота для подписчика, добавление/удаление из funnel — мастер-скилл умеет, body-схема некоторых методов требует доразведки в живую
- Отправка индивидуального сообщения подписчику (`application/vnd.api+json`)

**Не умеет (ограничения BotHelp API):**
- Создавать новых ботов / редактировать шаги
- Создавать новые авторассылки
- Массовые рассылки
- Читать текст сообщения внутри шага

## Установка

```bash
git clone https://github.com/atomachinskiy/claude-skill-bothelp.git ~/.claude/skills/bothelp
bash ~/.claude/skills/bothelp/scripts/bothelp-oauth-setup.sh
```

Мастер настройки cross-platform (macOS / Linux / WSL / Git Bash на Windows) — спросит `client_id` и `client_secret` твоего OAuth-приложения BotHelp, обменяет их на access_token, сохранит конфиг. Браузер не нужен (это `client_credentials` flow).

## Использование

После установки задавай Claude вопросы вроде:
- «Покажи все мои боты в BotHelp»
- «Где drop-off в воронке "Уроки по таргету"?»
- «Откуда подписчики приходят?»
- «Кто подписался за последний месяц?»
- «Обнови email подписчику 123 на new@example.com»

Claude вызовет нужный скрипт сам.

Прямые вызовы скриптов:
```bash
bash ~/.claude/skills/bothelp/scripts/bothelp-bots-list.sh --table
bash ~/.claude/skills/bothelp/scripts/bothelp-bot-steps.sh <bot_referral>
bash ~/.claude/skills/bothelp/scripts/bothelp-funnels-list.sh
bash ~/.claude/skills/bothelp/scripts/bothelp-subscribers-list.sh --since 2026-04-01
```

## Требования

- `bash` 3.2+
- `jq`, `curl`, `python3` (стандартный набор; `brew install jq` на macOS, `apt-get install jq` на Linux)
- OAuth-приложение в кабинете BotHelp (тип `client_credentials` / API integration)

## Безопасность

- Все секреты живут только в `~/.claude/secrets/bothelp-app.json` и `~/.claude/skills/bothelp/config/.env` с `chmod 600`
- Мастер настройки запускается локально в твоём терминале, секреты не передаются в чат с AI
- `.gitignore` исключает `.env` и любые credentials

## Лицензия

MIT — Andrey Tomachinskiy 2026

## Связанное

- [BotHelp API guide](https://help.bothelp.io/api-bothelp/)
- [OpenAPI 3.0.2 spec](https://main.bothelp.io/swagger/api.json)
- Полная документация особенностей API — в `SKILL.md`
