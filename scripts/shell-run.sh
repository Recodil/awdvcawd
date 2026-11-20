# Запуск оболочки с перезапуском при падении. Журнал: ~/.local/state/win11-shell/shell.log
DIR="$HOME/.local/state/win11-shell"
LOG="$DIR/shell.log"
mkdir -p "$DIR"
[ -f "$LOG" ] && mv -f "$LOG" "$LOG.old"

fails=0
while :; do
  [ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ] || exit 0
  start="$(date +%s)"
  echo "--- запуск $(date '+%F %T')" >> "$LOG"
  qs -p /etc/win11-shell >> "$LOG" 2>&1 &
  echo $! > "$DIR/shell.pid"
  wait $!
  code=$?
  echo "--- завершение, код $code" >> "$LOG"
  [ "$code" -eq 0 ] && exit 0
  now="$(date +%s)"
  if [ $((now - start)) -lt 20 ]; then
    fails=$((fails + 1))
  else
    fails=0
  fi
  if [ "$fails" -ge 3 ]; then
    # оболочка не поднимается — открываем терминал, чтобы экран не был пустым
    exec kitty --title "Оболочка не запустилась" sh -c \
      "echo 'Оболочка Win11 три раза подряд завершилась с ошибкой. Последние строки журнала:'; echo; tail -n 40 '$LOG'; echo; echo 'Выход из сеанса: Win+Shift+E'; exec \"\${SHELL:-sh}\""
  fi
  sleep 1
done
