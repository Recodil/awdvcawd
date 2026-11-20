#!/usr/bin/env bash
# Обновление одной командой (в установленной системе: win11-update).
#   win11-update                 применить изменения из /etc/nixos (пересборка с проверкой)
#   win11-update --system        то же + обновить все пакеты NixOS
#   win11-update архив.zip       поставить новую версию оболочки из скачанного архива или папки
#   win11-update github          скачать и поставить свежую версию из GitHub (адрес - в scripts/repo)
# Без пути команда сама ищет свежий win11-shell*.zip или папку win11-shell в "Загрузках".
set -uo pipefail

show_logo() {
  [ -n "${WIN11_LOGO_SHOWN:-}" ] && return 0
  export WIN11_LOGO_SHOWN=1
  printf "\033[1;36mЦентр обновления NixOS\033[0m\n"
  echo
}

show_logo

KIT=/etc/nixos/win11-shell-kit
NEWDIR="$HOME/.cache/win11-shell/new"
UPDATE_LOG="${XDG_CACHE_HOME:-$HOME/.cache}/win11-shell/update.log"
mkdir -p "${UPDATE_LOG%/*}"
: > "$UPDATE_LOG"

src=""; args=()
for a in "$@"; do
  case "$a" in
    --*) args+=("$a") ;;
    *) src="$a" ;;
  esac
done

if [ "$src" = github ]; then
  repo=""
  for rf in "$KIT/scripts/repo" "/etc/nixos/win11-shell/scripts/repo"; do
    [ -f "$rf" ] && repo="$(tr -d ' \t\r\n' < "$rf" 2>/dev/null)" && [ -n "$repo" ] && break
  done
  [ -n "$repo" ] || { echo "Адрес GitHub не задан: впишите владелец/репозиторий в $KIT/scripts/repo" >&2; exit 1; }
  rm -rf "$NEWDIR"; mkdir -p "$NEWDIR"
  echo "Скачиваю github.com/$repo ..." >> "$UPDATE_LOG"
  curl -fL -m 300 "https://github.com/$repo/archive/refs/heads/main.tar.gz" 2>> "$UPDATE_LOG" | tar -xz -C "$NEWDIR" >> "$UPDATE_LOG" 2>&1 \
    || { echo "Не удалось скачать github.com/$repo" >&2; exit 1; }
  src="$NEWDIR"
fi

if [ -z "$src" ]; then
  # ищем комплект новее установленного
  for c in "$HOME"/Downloads/win11-shell*.zip "$HOME"/Загрузки/win11-shell*.zip \
           "$HOME"/Downloads/win11-shell "$HOME"/Загрузки/win11-shell "$HOME"/Desktop/win11-shell; do
    [ -e "$c" ] || continue
    if [ ! -e "$KIT/install.sh" ] || [ "$c" -nt "$KIT/install.sh" ]; then
      if [ -z "$src" ] || [ "$c" -nt "$src" ]; then src="$c"; fi
    fi
  done
  [ -n "$src" ] && echo "Найдена новая версия: $src" >> "$UPDATE_LOG"
fi

# Проверка ядра до обновления
OLD_KERNEL="$(readlink -f /run/booted-system/kernel 2>/dev/null || true)"

echo -e "\033[1;36mУстановка обновления... Пожалуйста, подождите.\033[0m"
echo "   (весь журнал процесса записывается в $UPDATE_LOG)"
echo

if [ -n "$src" ]; then
  # установщик одним файлом (win11-shell-install.sh) распаковывает и запускает себя сам
  case "$src" in *.sh) [ -f "$src" ] && exec bash "$src" "${args[@]}" ;; esac
  if [ -f "$src" ]; then
    rm -rf "$NEWDIR"; mkdir -p "$NEWDIR"
    unzip -q "$src" -d "$NEWDIR" >> "$UPDATE_LOG" 2>&1 || { echo "Не удалось распаковать $src" >&2; exit 1; }
    inst="$(find "$NEWDIR" -maxdepth 3 -name install.sh | head -n 1)"
  else
    inst="$(find "$src" -maxdepth 3 -name install.sh | head -n 1)"
  fi
  [ -n "$inst" ] || { echo "В $src нет install.sh" >&2; exit 1; }
  bash "$inst" "${args[@]}" >> "$UPDATE_LOG" 2>&1
  rc=$?
else
  [ -e "$KIT/install.sh" ] || { echo "Оболочка ещё не установлена: запустите bash install.sh из скачанной папки." >&2; exit 1; }
  bash "$KIT/install.sh" --rebuild "${args[@]}" >> "$UPDATE_LOG" 2>&1
  rc=$?
fi

# Анализ необходимости перезапуска после обновления
if [ "$rc" -eq 0 ]; then
  echo -e "\033[1;32m==================================================\033[0m"
  echo -e "\033[1;32m        ОБНОВЛЕНИЕ УСПЕШНО УСТАНОВЛЕНО         \033[0m"
  echo -e "\033[1;32m==================================================\033[0m"
  echo
  NEW_KERNEL="$(readlink -f /run/current-system/kernel 2>/dev/null || true)"
  if [ -n "$OLD_KERNEL" ] && [ -n "$NEW_KERNEL" ] && [ "$OLD_KERNEL" != "$NEW_KERNEL" ]; then
    echo -e "\033[1;33mТРЕБУЕТСЯ ПЕРЕЗАГРУЗКА КОМПЬЮТЕРА\033[0m"
    echo "    Обновлено ядро Linux. Чтобы новая версия вступила в силу, перезагрузите ПК:"
    echo "    Пуск → Завершение работы → Перезагрузка (или выполните 'reboot')."
  elif [ -n "$src" ]; then
    echo -e "\033[1;36mПЕРЕЗАГРУЗКА ПК НЕ ТРЕБУЕТСЯ\033[0m"
    echo "    Обновлена оболочка Niri / Quickshell."
    echo "    Чтобы применить все изменения, достаточно выйти из профиля и зайти снова (Win+L → Выйти)."
  else
    echo -e "\033[1;32mОБНОВЛЕНИЕ ПРИМЕНЕНО НА ЛЕТУ\033[0m"
    echo "    Перезагрузка не требуется."
  fi
else
  echo -e "\033[1;31m==================================================\033[0m"
  echo -e "\033[1;31m        ОШИБКА ПРИ УСТАНОВКЕ ОБНОВЛЕНИЯ        \033[0m"
  echo -e "\033[1;31m==================================================\033[0m"
  echo "Код ошибки: $rc. Система осталась в прежнем состоянии."
  echo "Последние строки журнала ($UPDATE_LOG):"
  tail -n 15 "$UPDATE_LOG" 2>/dev/null | sed 's/^/    /'
fi

exit $rc
