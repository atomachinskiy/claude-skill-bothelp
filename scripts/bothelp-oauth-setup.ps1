# bothelp-oauth-setup.ps1 - Native PowerShell wizard for BotHelp OAuth setup.
# Runs in a separate PowerShell window opened by bothelp-launch-wizard.ps1.
# AI must NOT call this script directly - it would capture client_secret prompts.
#
# BotHelp uses client_credentials flow - no browser, no user-consent step.
# Just exchange client_id + client_secret for an access_token.

[CmdletBinding()]
param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$SkillDir    = Join-Path $env:USERPROFILE '.claude\skills\bothelp'
$SecretsDir  = Join-Path $env:USERPROFILE '.claude\secrets'
$SecretsFile = Join-Path $SecretsDir 'bothelp-app.json'
$EnvFile     = Join-Path $SkillDir 'config\.env'
$EnvExample  = Join-Path $SkillDir 'config\.env.example'

$OAuthBase = 'https://oauth.bothelp.io'
$ApiBase   = 'https://api.bothelp.io'

function Write-Step($msg) { Write-Host ""; Write-Host "[>] $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "[+] $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "[!] $msg" -ForegroundColor Yellow }
function Die($msg)        { Write-Host "[x] $msg" -ForegroundColor Red; exit 1 }

if (-not (Test-Path $SkillDir)) {
    Die "Папка $SkillDir не найдена. Сначала склонируй скилл: git clone https://github.com/atomachinskiy/claude-skill-bothelp.git $SkillDir"
}

Write-Host ""
Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host "  BotHelp API - мастер настройки OAuth (PowerShell, без Git Bash)" -ForegroundColor Cyan
Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host ""

New-Item -ItemType Directory -Path $SecretsDir -Force | Out-Null

if ((Test-Path $SecretsFile) -and -not $Force) {
    Write-Warn "Найден существующий $SecretsFile"
    $ans = Read-Host 'Перезаписать credentials? [y/N]'
    if ($ans -notmatch '^[Yy]') { Die "Отменено пользователем." }
}

# ----- Step 1: instructions -----
Write-Host ""
Write-Host "=== Шаг 1: создать OAuth-приложение в BotHelp ===" -ForegroundColor Yellow
Write-Host ""
Write-Host "  1. Открой кабинет BotHelp: https://app.bothelp.io"
Write-Host "  2. Перейди в раздел: Настройки -> Разработчикам -> API -> Создать приложение"
Write-Host "     (точное расположение может отличаться - ищи раздел про OAuth-приложения)"
Write-Host "  3. Тип авторизации: OAuth 2.0 / API integration / Server-to-server"
Write-Host "  4. Скопируй client_id и client_secret - нужны на шаге 2"
Write-Host ""
Write-Host "  redirect_uri и user-consent НЕ требуются - у BotHelp client_credentials flow,"
Write-Host "  это машина-машина, без браузерной авторизации."
Write-Host ""
Read-Host 'Готов? Жми Enter чтобы перейти к шагу 2'

# ----- Step 2: credentials -----
Write-Step "Шаг 2: ввод client_id и client_secret"
Write-Host "  client_id - публичный, можно вставить как обычно"
Write-Host "  client_secret - будет скрыт при вводе"
Write-Host ""

$clientId = Read-Host 'client_id'
if (-not $clientId) { Die "client_id пустой" }

$clientSecretSecure = Read-Host 'client_secret (ввод скрыт)' -AsSecureString
$clientSecret = [System.Net.NetworkCredential]::new('', $clientSecretSecure).Password
if (-not $clientSecret) { Die "client_secret пустой" }

# Save secrets BEFORE token exchange so retries don't re-prompt
$createdAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$secretsPayload = [ordered]@{
    client_id     = $clientId
    client_secret = $clientSecret
    created_at    = $createdAt
}
$secretsJson = $secretsPayload | ConvertTo-Json -Depth 3
[System.IO.File]::WriteAllText($SecretsFile, $secretsJson, (New-Object System.Text.UTF8Encoding($false)))

try {
    $acl = New-Object System.Security.AccessControl.FileSecurity
    $acl.SetAccessRuleProtection($true, $false)
    $me = "$env:USERDOMAIN\$env:USERNAME"
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($me, 'FullControl', 'Allow')))
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule('NT AUTHORITY\SYSTEM', 'FullControl', 'Allow')))
    Set-Acl -Path $SecretsFile -AclObject $acl
} catch {}
Write-Ok "Сохранил $SecretsFile (доступ ограничен)"

# ----- Step 3: exchange for access_token -----
Write-Step "Шаг 3: обмен credentials на access_token (POST /oauth2/token)"

$body = @{
    grant_type    = 'client_credentials'
    client_id     = $clientId
    client_secret = $clientSecret
}

try {
    $resp = Invoke-RestMethod -Uri "$OAuthBase/oauth2/token" `
                              -Method Post `
                              -ContentType 'application/x-www-form-urlencoded' `
                              -Body $body `
                              -TimeoutSec 30
} catch {
    $statusCode = $null
    if ($_.Exception.Response) { $statusCode = [int]$_.Exception.Response.StatusCode }
    Write-Warn "BotHelp ответил HTTP $statusCode : $($_.Exception.Message)"
    Write-Host ""
    Write-Host "Что проверить:" -ForegroundColor Yellow
    Write-Host "  - client_id и client_secret скопированы без лишних пробелов"
    Write-Host "  - OAuth-приложение в BotHelp активировано (не draft)"
    Write-Host "  - У приложения тип 'client_credentials / API integration'"
    Die "Не удалось получить токен. Перезапусти мастер с правильными credentials."
}

$accessToken = $resp.access_token
$expiresIn   = if ($resp.expires_in) { [int]$resp.expires_in } else { 3600 }
$tokenType   = if ($resp.token_type) { $resp.token_type } else { 'Bearer' }
$nowEpoch    = [int][double]::Parse((Get-Date -UFormat %s))
$expiresAt   = $nowEpoch + $expiresIn

if (-not $accessToken) { Die "В ответе нет access_token: $($resp | ConvertTo-Json)" }
Write-Ok "Получен access_token (живёт $expiresIn секунд)"

# ----- Step 4: write .env -----
Write-Step "Шаг 4: записываю $EnvFile"

$ConfigDir = Split-Path $EnvFile -Parent
New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null

# Start from .env.example if exists, then override our keys
$envLines = @()
if ((Test-Path $EnvFile)) {
    $envLines = Get-Content $EnvFile
} elseif (Test-Path $EnvExample) {
    $envLines = Get-Content $EnvExample
}

$desired = [ordered]@{
    BOTHELP_ACCESS_TOKEN     = $accessToken
    BOTHELP_TOKEN_TYPE       = $tokenType
    BOTHELP_TOKEN_EXPIRES_AT = $expiresAt
    BOTHELP_API_BASE         = $ApiBase
    BOTHELP_OAUTH_BASE       = $OAuthBase
}

$out = @()
$seen = @{}
foreach ($ln in $envLines) {
    if ($ln -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=') {
        $k = $Matches[1]
        if ($desired.Contains($k)) {
            $out += "$k=$($desired[$k])"
            $seen[$k] = $true
            continue
        }
    }
    $out += $ln
}
foreach ($k in $desired.Keys) {
    if (-not $seen.ContainsKey($k)) { $out += "$k=$($desired[$k])" }
}

$envContent = ($out -join [Environment]::NewLine) + [Environment]::NewLine
[System.IO.File]::WriteAllText($EnvFile, $envContent, (New-Object System.Text.UTF8Encoding($false)))

try {
    $acl = New-Object System.Security.AccessControl.FileSecurity
    $acl.SetAccessRuleProtection($true, $false)
    $me = "$env:USERDOMAIN\$env:USERNAME"
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($me, 'FullControl', 'Allow')))
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule('NT AUTHORITY\SYSTEM', 'FullControl', 'Allow')))
    Set-Acl -Path $EnvFile -AclObject $acl
} catch {}

Write-Ok "Записал $EnvFile"

# ----- Step 5: sanity-check -----
Write-Step "Шаг 5: sanity-check - GET /v1/bots"

try {
    $headers = @{ Authorization = "Bearer $accessToken"; Accept = 'application/json' }
    $sanity = Invoke-RestMethod -Uri "$ApiBase/v1/bots" -Headers $headers -TimeoutSec 20
    $count = '?'
    if ($sanity -is [System.Array]) { $count = $sanity.Count }
    elseif ($sanity.data) { $count = $sanity.data.Count }
    Write-Ok "BotHelp отвечает. Активных ботов: $count"
} catch {
    Write-Warn "Sanity-check упал: $($_.Exception.Message)"
    Write-Warn "Конфиг сохранён - попробуй позже: ~/.claude/skills/bothelp/scripts/bothelp-bots-list.sh"
}

Write-Host ""
Write-Host "===============================================================" -ForegroundColor Green
Write-Host "  + BotHelp настроен. Можно работать." -ForegroundColor Green
Write-Host "===============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Конфиг:           $EnvFile"
Write-Host "  Credentials:      $SecretsFile"
Write-Host "  Auto-refresh:     встроен в _common.sh (за 60с до истечения)"
Write-Host ""
Write-Host "Попробуй: 'Покажи моих ботов в BotHelp', 'Воронки в BotHelp', 'Подписчики бота X'"
Write-Host ""
Read-Host 'Нажми Enter чтобы закрыть это окно'
