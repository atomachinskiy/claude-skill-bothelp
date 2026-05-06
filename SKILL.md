---
name: bothelp
description: Анализ воронок, подписчиков, рассылок и операторская работа в BotHelp (мультимессенджерные чат-боты — Telegram, VK, Facebook, Instagram, WhatsApp). Используй когда пользователь просит посмотреть аналитику BotHelp-канала, разобрать активные сценарии, выгрузить подписчиков, обновить кастомные поля или теги, отправить индивидуальное сообщение, запустить/остановить бота для подписчика или добавить в авторассылку. Работает через OAuth client_credentials, токен живёт 1 час, скилл сам автоматически обновляет.
---

# BotHelp — AI-аналитик, AI-сегментатор и AI-оператор для чат-ботов

Скилл подключается к BotHelp Open API (`api.bothelp.io`) и даёт AI-агенту доступ к **аналитике**, **управлению подписчиками** и **операторским действиям** (отправка сообщений, запуск ботов, добавление в воронки) в кабинете BotHelp.

## Когда использовать

- Карта активных ботов и шагов внутри них
- Список авторассылок (funnels) с метаданными
- Экспорт подписчиков с фильтрами (период, email, phone)
- Обновление common fields и custom fields подписчика
- Установка/снятие тегов для сегментации
- Индивидуальная рассылка сообщения подписчику
- Триггер запуска или остановки бота для конкретного подписчика
- Добавление/удаление подписчика из автоворонки

## Prereqs

- `jq`, `curl`, `python3` (для расчёта expires_at)
- `~/.claude/secrets/bothelp-app.json` — `client_id`, `client_secret`
- `~/.claude/skills/bothelp/config/.env` — `BOTHELP_ACCESS_TOKEN`, `BOTHELP_TOKEN_EXPIRES_AT`

Полная инструкция — `config/setup-guide.md`.

Если у пользователя нет токена — запусти мастер:

```bash
bash ~/.claude/skills/bothelp/scripts/bothelp-oauth-setup.sh
```

Мастер интерактивно собирает `client_id` (видимый ввод) и `client_secret` (`read -s`, скрытый), делает POST на `oauth.bothelp.io/oauth2/token` с `grant_type=client_credentials`, сохраняет токен с временем истечения. Браузер не нужен (это machine-to-machine flow, не пользовательский OAuth с consent-страницей).

## ВАЖНО: что МОЖНО и что НЕЛЬЗЯ через BotHelp API

### ✅ ЧТЕНИЕ — полностью работает (проверено)

- `GET /v1/bots` — массив `[{title, referral}]` всех активных ботов
- `GET /v1/bots/{bot_referral}/steps` — массив `[{title, referral}]` шагов
- `GET /v1/funnels` — массив активных авторассылок (`[]` если нет)
- `GET /v1/subscribers` — `{data: [...], paging: {cursor: {after: N}, next: "after=N"}}`. По 100 подписчиков на страницу. Поля subscriber: `id` + `cuid` + `userId` (три ID), email, phone, name, channelType (telegram/instagram/...), tags[], 5 utm*, prodamusProfileId, yaClientId, subscribed, createdAt. Фильтры: `?createdAtAfter=epoch`, `?after=cursor_id`, `?email=`, `?phone=`.

### ✅ WRITE — частично работает (проверено JSON Patch RFC 6902)

`PATCH /v1/subscribers/{id}` принимает массив операций — НЕ обычный JSON merge.

**Подтверждено работает:**
- `op:replace path:/name value:"..."` — обновить имя ✓
- `op:replace path:/email value:"..."` ✓
- `op:replace path:/phone value:"..."` ✓

**Реальные тела других write-методов из OpenAPI (не верифицированы вживую — мастер-скилл их умеет, но реверс схемы может потребоваться):**
- `POST /v1/subscribers/{id}/bot` body `{botReferral, stepReferral}` — запустить бота с шага (тело размечено в спеке)
- `DELETE /v1/subscribers/{id}/bot` — остановить бота
- `POST /v1/subscribers/{id}/funnel` — добавить в авторассылку
- `DELETE /v1/subscribers/{id}/funnel` — убрать из авторассылки
- `PATCH /v1/subscribers/{id}/customFields` — обновить кастомные поля
- `POST /v1/subscribers/{id}/messages` — отправить индивидуальное сообщение (`application/vnd.api+json`)

### ⚠️ ТЕГИ ПОДПИСЧИКА — точная формула не разгадана

Все стандартные варианты JSON Patch на `/tags` либо возвращают «Patch instruction not recognized», либо `success:true` без реального изменения данных в `/v1/subscribers` (silent fail). До появления документированной схемы или подтверждения от поддержки BotHelp **рекомендуется использовать UI BotHelp для постановки/снятия тегов**. Чтение тегов через `/v1/subscribers` работает корректно — это полноценный канал для аналитики и сегментации.

### ❌ ПРИНЦИПИАЛЬНО НЕ ДОСТУПНО через API

- Создавать новых ботов / шаги (нет `bots/create`, `steps/create`)
- Редактировать содержимое шага (текст, кнопки, медиа)
- Создавать новые авторассылки (нет `funnels/create`) — только добавлять в существующие
- Массовые рассылки (broadcast) — отправка только индивидуально через `subscribers/{id}/messages`
- Читать точный текст сообщения внутри шага из API — только title + referral

### Особенности обращений (зафиксировано на практике)

- **Trailing slash непоследовательный.** `/v1/bots` хочет `/`, `/v1/bots/{ref}/steps` — без `/`. `_common.sh` использует `curl -L` чтобы следовать 301 в любую сторону.
- **OAuth2 client_credentials**, токен 1 час. Refresh = повторный POST с теми же `client_id`+`client_secret`. `_common.sh` обновляет автоматически за 60с до истечения.
- **Rate limit:** 10 req/sec на bots/funnels/messages-by-id/customFields, 25 req/sec на messages-by-cuid/funnel-ops/bot-ops. Скилл ставит задержку ~120мс между запросами.

### Реальные сценарии использования

1. **Аналитика + сегментация:** AI читает `/v1/bots/{ref}/steps`, находит проблемные шаги; через `PATCH /subscribers/{id}` ставит сегментирующий тег.

2. **Re-engagement:** AI находит молчунов (нет активности > N дней) → ставит тег → через `POST /subscribers/{id}/funnel` добавляет в re-engagement авторассылку.

3. **Reactivation одиночный:** для VIP-подписчика AI шлёт индивидуальное сообщение через `POST /subscribers/{id}/messages` или триггерит спецбот `POST /subscribers/{id}/bot` со step.

Позиционирование скилла: **AI-аналитик + AI-сегментатор + AI-оператор**.

## Роутер задач

| Задача | Скрипт | Пример |
|---|---|---|
| Sanity-check токена | `bothelp-bots-list.sh` | «Проверь BotHelp работает?» |
| Карта всех ботов | `bothelp-bots-list.sh` | «Какие боты у меня?» |
| Шаги одного бота | `bothelp-bot-steps.sh <bot_referral>` | «Покажи шаги бота X» |
| Список авторассылок | `bothelp-funnels-list.sh` | «Какие funnels активны?» |
| Экспорт подписчиков | `bothelp-subscribers-list.sh [--email --phone --after --since]` | «Выгрузи подписчиков за апрель» |
| Обновить subscriber | `bothelp-subscriber-update.sh <id> --json '...'` | «Поставь тег молчун подписчику 123» |
| Обновить кастомные поля | `bothelp-subscriber-customfields.sh <id> --json '...'` | «Запиши в кастомное поле X» |
| Отправить сообщение | `bothelp-subscriber-message.sh <id> --json '...'` | «Напиши подписчику 123 текст Y» |
| Запустить бота | `bothelp-subscriber-bot-run.sh <id> <bot_ref> [<step_ref>]` | «Запусти бот X для подписчика 123» |
| Остановить бота | `bothelp-subscriber-bot-stop.sh <id>` | «Останови бота для 123» |
| Добавить в funnel | `bothelp-subscriber-funnel-add.sh <id> --json '...'` | «Добавь 123 в re-engagement funnel» |
| Убрать из funnel | `bothelp-subscriber-funnel-remove.sh <id>` | «Убери 123 из funnel» |
| Любой raw-запрос | `bothelp-call.sh <METHOD> <path> [body-json]` | Когда нужен метод не из списка |

## Как вызывать

```bash
bash ~/.claude/skills/bothelp/scripts/SCRIPT_NAME.sh ARGS
```

Общие флаги: `--json` (сырой JSON), `--full` (без обрезки 30 строк).

`_common.sh` сам проверяет срок действия токена перед запросом и автоматически обновляет (повторный POST на `oauth2/token`) если до истечения < 60 секунд. Refresh-токена в схеме `client_credentials` нет — вместо него повторное обращение с `client_id` + `client_secret`.

## Ограничения

- **Token TTL: 1 час.** `_common.sh` обновляет автоматически. Между ручными запусками тоже всё ок — мастер запускать заново НЕ нужно.
- **Rate limits (документировано BotHelp):**
  - 10 req/sec — для custom fields, bot steps, funnels, messages (по subscriber_id), bots
  - 25 req/sec — для messages по CUID, операций funnel/bot
  - `_common.sh` ставит задержку ~0.12с между запросами (запас под 10 req/sec).
- **Один токен = один кабинет.** Если у пользователя несколько workspace — токен на каждый отдельно.
- **Cross-domain запрещён.** API не работает из браузерного JS — только server-to-server.
- **Content-type для messages — `application/vnd.api+json`** (не обычный JSON). Скрипт `bothelp-subscriber-message.sh` сам подставляет правильный header.

## Файлы скилла

```
~/.claude/skills/bothelp/
├── SKILL.md                                # этот файл
├── config/
│   ├── .env.example                        # шаблон конфига
│   ├── .env                                # реальный конфиг (gitignored)
│   └── setup-guide.md                      # пошаговая инструкция подключения
├── scripts/
│   ├── _common.sh                          # обёртка с auto-refresh токена + rate limit
│   ├── bothelp-oauth-setup.sh              # интерактивный мастер настройки
│   ├── bothelp-bots-list.sh                # GET /v1/bots
│   ├── bothelp-bot-steps.sh                # GET /v1/bots/{ref}/steps
│   ├── bothelp-funnels-list.sh             # GET /v1/funnels
│   ├── bothelp-subscribers-list.sh         # GET /v1/subscribers с пагинацией
│   ├── bothelp-subscriber-update.sh        # PATCH /v1/subscribers/{id}
│   ├── bothelp-subscriber-customfields.sh  # PATCH /v1/subscribers/{id}/customFields
│   ├── bothelp-subscriber-message.sh       # POST /v1/subscribers/{id}/messages
│   ├── bothelp-subscriber-bot-run.sh       # POST /v1/subscribers/{id}/bot
│   ├── bothelp-subscriber-bot-stop.sh      # DELETE /v1/subscribers/{id}/bot
│   ├── bothelp-subscriber-funnel-add.sh    # POST /v1/subscribers/{id}/funnel
│   ├── bothelp-subscriber-funnel-remove.sh # DELETE /v1/subscribers/{id}/funnel
│   └── bothelp-call.sh                     # raw-вызов любого метода
└── cache/                                  # кеш (если используется)
```

## Связанная документация

- BotHelp API guide: https://help.bothelp.io/api-bothelp/
- OpenAPI 3.0.2 spec: https://main.bothelp.io/swagger/api.json
- Swagger UI: https://main.bothelp.io/swagger
- Token endpoint: `POST https://oauth.bothelp.io/oauth2/token` (`grant_type=client_credentials`)
- Base URL: `https://api.bothelp.io`
