#!/usr/bin/env bash
# bothelp-launch-wizard.sh — открывает отдельное окно терминала с подгруженной
# командой запуска интерактивного мастера OAuth-настройки.
#
# Зачем: AI-ассистент (например Claude Code) может запустить этот скрипт через Bash tool,
# и у пользователя САМ откроется отдельный Terminal/PowerShell с командой setup.sh.
# Пользователь вводит client_id/client_secret в этом отдельном окне (не в чате с AI),
# мастер сохраняет токен в .env. AI секреты не видит — соблюдается граница безопасности.
#
# Cross-platform: macOS / Linux / WSL / Git Bash на Windows.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WIZARD="$SCRIPT_DIR/bothelp-oauth-setup.sh"

[ -f "$WIZARD" ] || { echo "❌ Не найден $WIZARD"; exit 1; }

OS="$(uname -s 2>/dev/null || echo unknown)"

case "$OS" in
  Darwin)
    # macOS: открываем Terminal.app с командой через AppleScript.
    # Экранируем путь для AppleScript-строки.
    ESCAPED_PATH="${WIZARD//\"/\\\"}"
    /usr/bin/osascript <<EOF
tell application "Terminal"
    activate
    do script "bash \"$ESCAPED_PATH\""
end tell
EOF
    echo "✅ Открыл Terminal.app с мастером настройки. Перейди в новое окно и следуй инструкциям там."
    ;;

  Linux|WSL*)
    # Linux: пробуем популярные эмуляторы.
    if command -v gnome-terminal >/dev/null 2>&1; then
      gnome-terminal -- bash -c "bash '$WIZARD'; echo; read -p 'Нажми Enter чтобы закрыть...'"
    elif command -v konsole >/dev/null 2>&1; then
      konsole -e bash -c "bash '$WIZARD'; echo; read -p 'Нажми Enter чтобы закрыть...'"
    elif command -v xterm >/dev/null 2>&1; then
      xterm -e bash -c "bash '$WIZARD'; echo; read -p 'Нажми Enter чтобы закрыть...'"
    elif command -v xfce4-terminal >/dev/null 2>&1; then
      xfce4-terminal -e "bash -c \"bash '$WIZARD'; echo; read -p 'Нажми Enter чтобы закрыть...'\""
    else
      echo "❌ Не нашёл терминал-эмулятор. Запусти руками:"
      echo "    bash \"$WIZARD\""
      exit 1
    fi
    echo "✅ Открыл терминал с мастером. Перейди в новое окно."
    ;;

  MINGW*|MSYS*|CYGWIN*)
    # Git Bash на Windows: запускаем PowerShell с командой.
    # cygpath -w конвертирует /c/Users/... в C:\Users\...
    NATIVE_WIZARD="$(cygpath -w "$WIZARD")"
    GIT_BASH="$(command -v bash || echo 'C:\Program Files\Git\bin\bash.exe')"
    NATIVE_BASH="$(cygpath -w "$GIT_BASH" 2>/dev/null || echo "$GIT_BASH")"

    powershell.exe -NoProfile -Command "Start-Process powershell -ArgumentList '-NoExit','-Command',\"& '$NATIVE_BASH' '$NATIVE_WIZARD'\""
    echo "✅ Открыл PowerShell-окно с мастером. Перейди в новое окно."
    ;;

  *)
    echo "❌ Не распознал ОС ($OS). Запусти мастер руками:"
    echo "    bash \"$WIZARD\""
    exit 1
    ;;
esac
