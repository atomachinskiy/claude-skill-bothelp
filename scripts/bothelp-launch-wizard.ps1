# bothelp-launch-wizard.ps1 - Spawn separate PowerShell window running
# bothelp-oauth-setup.ps1. Used on Windows so client_secret never enters
# the AI assistant's transcript.
#
# AI calls this script via Bash tool:
#   powershell -ExecutionPolicy Bypass -File bothelp-launch-wizard.ps1
#
# A new PowerShell window opens. User enters credentials there. AI never sees them.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Setup     = Join-Path $ScriptDir 'bothelp-oauth-setup.ps1'

if (-not (Test-Path $Setup)) {
    Write-Host "[x] Не найден $Setup" -ForegroundColor Red
    exit 1
}

$psExe = (Get-Command powershell.exe -ErrorAction SilentlyContinue).Source
if (-not $psExe) { $psExe = 'powershell.exe' }

Start-Process -FilePath $psExe `
              -ArgumentList @(
                  '-NoExit',
                  '-ExecutionPolicy', 'Bypass',
                  '-File', "`"$Setup`""
              )

Write-Host "[+] Открыл отдельное окно PowerShell с мастером настройки BotHelp." -ForegroundColor Green
Write-Host "    Перейди в новое окно и следуй инструкциям там."
Write-Host "    client_id / client_secret вводятся там, в этот чат они не попадут."
