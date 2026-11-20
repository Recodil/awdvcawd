# win11-updater - мини-приложение обновления оболочки.
#   win11-updater find          найти архивы win11-shell*.zip в "Загрузках" и на рабочем столе
#   win11-updater run [архив]   установить (откроется окно с ходом работы; спросит пароль)
#   win11-updater system        обновить ещё и пакеты NixOS
#   win11-updater watch         (служба) заметить новый архив и открыть окно обновления
# Строки find: состояние<TAB>путь<TAB>дата;  состояние: new - новее установленного, old - нет.
export PATH="$PATH:/run/current-system/sw/bin"
KIT=/etc/nixos/win11-shell-kit
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/win11-shell"
mkdir -p "$STATE"

candidates() {
  local d f
  for d in "$HOME/Downloads" "$HOME/Загрузки" "$HOME/Desktop" "$HOME/Рабочий стол" "$HOME"; do
    [ -d "$d" ] || continue
    for f in "$d"/win11-shell*.zip; do [ -f "$f" ] && printf '%s\t%s\n' "$(stat -c %Y "$f")" "$f"; done
  done | sort -rn | head -n 8
}
is_new() { [ ! -e "$KIT/install.sh" ] || [ "$1" -nt "$KIT/install.sh" ]; }
# архив цел и это действительно комплект оболочки
valid() { unzip -tq "$1" >/dev/null 2>&1 && unzip -l "$1" 2>/dev/null | grep -q 'install\.sh$'; }

case "${1:-}" in
  find)
    candidates | while IFS="$(printf '\t')" read -r t f; do
      if is_new "$f"; then st=new; else st=old; fi
      printf '%s\t%s\t%s\n' "$st" "$f" "$(date -d "@$t" '+%d.%m.%Y %H:%M')"
    done ;;
  run|system)
    file="${2:-}"; flag=""
    [ "$1" = system ] && { flag="--system"; file=""; }
    file="${file#file://}"
    if [ -n "$file" ]; then
      [ -f "$file" ] || { notify-send -a win11-shell "Обновление" "Нет такого файла: $file"; exit 1; }
      valid "$file" || { notify-send -a win11-shell "Обновление" "Это не архив оболочки или он скачан не до конца: ${file##*/}"; exit 1; }
    fi
    # одно окно обновления за раз
    exec 9> "$STATE/updater.lock"
    flock -n 9 || { notify-send -a win11-shell "Обновление" "Обновление уже идёт"; exit 0; }
    kitty --title "Обновление оболочки" sh -c '
      echo "== Обновление оболочки =="; echo
      if [ -n "$1" ]; then echo "Архив: $1"; win11-update $2 "$1"; else win11-update $2; fi
      code=$?; echo
      if [ "$code" -eq 0 ]; then echo "Готово. Если просили перезагрузиться - перезагрузите компьютер."
      else echo "Обновление не удалось (код $code). Система осталась прежней. Текст выше пришлите разработчику."; fi
      echo; printf "Нажмите Enter, чтобы закрыть окно. "; read -r _' sh "$file" "$flag"
    ;;
  watch)
    sleep 3      # браузер дописывает файл
    best="$(candidates | head -n 1 | cut -f2)"
    [ -n "$best" ] || exit 0
    is_new "$best" || exit 0
    key="$best $(stat -c %Y "$best")"
    [ "$(cat "$STATE/updater.seen" 2>/dev/null)" = "$key" ] && exit 0
    # ждём, пока архив докачается (до 2 минут)
    i=0; until valid "$best"; do i=$((i + 1)); [ "$i" -gt 24 ] && exit 0; sleep 5; done
    printf '%s\n' "$key" > "$STATE/updater.seen"
    qs -p /etc/win11-shell ipc call shell updateFound >/dev/null 2>&1 \
      || notify-send -a win11-shell "Обновление" "Найден новый архив оболочки: ${best##*/}. Откройте \"Параметры → Обновление\"." ;;
  *) sed -n '1,6p' "$0" | sed 's/^# \{0,1\}//' ;;
esac
