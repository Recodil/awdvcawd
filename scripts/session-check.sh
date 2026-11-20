# Проверка сеанса: запускается niri при входе. Сообщает сторожу, появилась ли панель задач.
RUN=/run/win11-shell
[ -d "$RUN" ] || exit 0
LOG="$HOME/.local/state/win11-shell/shell.log"

alive() {
  pid="$(cat "$HOME/.local/state/win11-shell/shell.pid" 2>/dev/null)" || return 1
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

has_bar() {
  out="$(niri msg --json layers 2>/dev/null)" || return 2
  echo "$out" | grep -q 'win11-taskbar'
}

i=0
while [ "$i" -lt 30 ]; do
  sleep 2
  i=$((i + 1))
  has_bar
  rc=$?
  if [ "$rc" -eq 2 ]; then
    # старый niri без команды layers: достаточно того, что оболочка не падает
    alive || continue
  elif [ "$rc" -ne 0 ]; then
    continue
  fi
  # оболочка должна прожить ещё несколько секунд
  sleep 6
  has_bar
  rc=$?
  if [ "$rc" -eq 0 ] || { [ "$rc" -eq 2 ] && alive; }; then
    : > "$RUN/ok"
    exit 0
  fi
done
{
  echo "панель задач не появилась за 60 с"
  [ -f "$LOG" ] && tail -n 5 "$LOG"
} > "$RUN/fail"
exit 1
