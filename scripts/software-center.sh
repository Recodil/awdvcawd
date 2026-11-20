#!/usr/bin/env bash
# Установщик графического магазина приложений (GUI менеджер пакетов) для NixOS и Niri.
#   bash software-center.sh            установить и запустить
#   bash software-center.sh install    только установить
#   bash software-center.sh run        запустить
#   bash software-center.sh remove     удалить
# Ставится в профиль пользователя (~/.local): пароль root и пересборка системы не нужны.
set -euo pipefail

say() { printf '%s\n' "$*"; }
die() { printf 'Ошибка: %s\n' "$*" >&2; exit 1; }

command -v nix-env >/dev/null || die "это не NixOS: нет команды nix-env"

DIR="${XDG_DATA_HOME:-$HOME/.local/share}/nix-software-center"
BIN="${XDG_BIN_HOME:-$HOME/.local/bin}/software-center"
DESK="${XDG_DATA_HOME:-$HOME/.local/share}/applications/software-center.desktop"
LOG="${XDG_CACHE_HOME:-$HOME/.cache}/software-center.log"
mkdir -p "${LOG%/*}" "$(dirname "$BIN")" "$(dirname "$DESK")"

install_store() {
  if command -v nix-software-center >/dev/null 2>&1; then
    say "Графический центр пакетов nix-software-center уже установлен в системе."
  else
    say "==> Установка графического центра пакетов (nix-software-center)..."
    command -v git >/dev/null 2>&1 || nix-env -f '<nixpkgs>' -iA git >>"$LOG" 2>&1 || true

    if [ ! -d "$DIR" ]; then
      say "Клонирую репозиторий snowfallorg/nix-software-center..."
      git clone --depth 1 https://github.com/snowfallorg/nix-software-center "$DIR" >>"$LOG" 2>&1 || die "Не удалось клонировать репозиторий. Журнал: $LOG"
    else
      say "Обновляю исходники в $DIR..."
      ( cd "$DIR" && git pull --ff-only >>"$LOG" 2>&1 || true )
    fi

    say "Сборка и установка в профиль пользователя (займёт несколько минут)..."
    # собираем с низким приоритетом ввода-вывода (ionice/nice), чтобы система и мышь не зависали
    if ( command -v ionice >/dev/null && ionice -c 3 nice -n 15 nix-env -f "$DIR" -i nix-software-center || nix-env -f "$DIR" -i nix-software-center ) >>"$LOG" 2>&1; then
      say "nix-software-center успешно собран и установлен."
    else
      say "Сборка из исходников не прошла, пробую через nix run/profile..."
      nix --extra-experimental-features "nix-command flakes" profile install github:snowfallorg/nix-software-center >>"$LOG" 2>&1 || {
        say "Внимание: nix-software-center не собрался. Устанавливаю запасной легковесный GUI (Bauh)..."
        nix-env -f '<nixpkgs>' -iA bauh >>"$LOG" 2>&1 || die "Не удалось установить GUI-менеджер. Журнал: $LOG"
      }
    fi
  fi

  # Создаём удобный скрипт запуска software-center
  cat > "$BIN" <<'RUNNER'
#!/usr/bin/env bash
if command -v nix-software-center >/dev/null 2>&1; then
  exec nix-software-center "$@"
elif command -v bauh >/dev/null 2>&1; then
  exec bauh "$@"
elif command -v gnome-software >/dev/null 2>&1; then
  exec gnome-software "$@"
else
  echo "GUI менеджер не найден. Переустановите: bash ~/Загрузки/software-center.sh" >&2
  exit 1
fi
RUNNER
  chmod +x "$BIN"

  # Создаём .desktop файл для меню "Пуск" и панели задач
  cat > "$DESK" <<ENTRY
[Desktop Entry]
Name=Магазин
GenericName=Установка и удаление программ
Comment=Графический менеджер пакетов для NixOS и Niri
Exec=$BIN %U
Icon=system-software-install
Terminal=false
Type=Application
Categories=System;PackageManager;Settings;
StartupNotify=true
ENTRY

  hash -r
  say "Готово! Магазин программ установлен."
  say "Команда для запуска: software-center"
  say "Значок \"Магазин\" появится в меню \"Пуск\" и на панели задач."
}

run_store() {
  if [ -x "$BIN" ]; then
    exec "$BIN" "$@"
  elif command -v nix-software-center >/dev/null 2>&1; then
    exec nix-software-center "$@"
  elif command -v bauh >/dev/null 2>&1; then
    exec bauh "$@"
  else
    install_store
    exec "$BIN" "$@"
  fi
}

remove_store() {
  say "Удаление магазина программ..."
  nix-env -e nix-software-center >>"$LOG" 2>&1 || true
  nix-env -e bauh >>"$LOG" 2>&1 || true
  rm -rf "$DIR" "$BIN" "$DESK"
  say "Магазин удалён."
}

case "${1:-all}" in
  install) install_store ;;
  run) run_store ;;
  remove) remove_store ;;
  all)
    install_store
    say "Запуск магазина..."
    run_store "$@" &
    ;;
  *)
    sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'
    ;;
esac
