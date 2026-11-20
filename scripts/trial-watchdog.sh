# Сторож пробного запуска (работает от root, запускается systemd).
# Если новая система не подтвердила, что рабочий стол загрузился, — возвращает прежнюю.
STATE=/var/lib/win11-shell
RUN=/run/win11-shell
LOGDIR=/var/log/win11-shell
PROFILE=/nix/var/nix/profiles/system

[ -f "$STATE/trial" ] || exit 0

PHASE=""; OLD=""; NEW=""; MODE=""
. "$STATE/trial"

mkdir -p "$LOGDIR" "$RUN"
chmod 1777 "$RUN"
CUR="$(readlink -f /run/current-system)"

result() { echo "$1" > "$STATE/last-result"; echo "win11-trial: $1"; }

if [ "$CUR" != "$NEW" ]; then
  # проверка была прервана перезагрузкой — мы уже в другой системе
  result "failed mode=$MODE reason=перезагрузка во время проверки"
  rm -f "$STATE/trial"
  exit 0
fi

rm -f "$RUN/ok" "$RUN/fail"

if [ "$PHASE" = live ]; then
  LIMIT=300
  systemctl restart display-manager.service || true
else
  LIMIT=600
fi

save_log() {
  f="$LOGDIR/fail-$(date +%Y%m%d-%H%M%S).log"
  {
    echo "причина: $1"
    echo "этап: $PHASE, режим: $MODE"
    echo "система: $NEW"
    echo; echo "== сбойные службы =="
    systemctl --failed --no-pager 2>&1
    echo; echo "== экран входа =="
    systemctl status display-manager.service --no-pager -n 0 2>&1
    journalctl -b -u display-manager.service --no-pager 2>&1 | tail -n 150
    echo; echo "== niri =="
    journalctl -b --no-pager 2>&1 | grep -i niri | tail -n 80
    echo; echo "== ошибки загрузки =="
    journalctl -b -p err --no-pager 2>&1 | tail -n 150
    for l in /home/*/.local/state/win11-shell/shell.log; do
      [ -f "$l" ] || continue
      echo; echo "== $l =="
      tail -n 120 "$l"
    done
  } > "$f" 2>&1
  echo "$f"
}

fail() {
  f="$(save_log "$1")"
  result "failed mode=$MODE phase=$PHASE log=$f reason=$1"
  rm -f "$STATE/trial"
  if [ "$PHASE" = boot ] && [ -x "$OLD/bin/switch-to-configuration" ]; then
    nix-env -p "$PROFILE" --set "$OLD" && "$OLD/bin/switch-to-configuration" boot
  fi
  sync
  systemctl reboot
  exit 0
}

t=0
while [ "$t" -lt "$LIMIT" ]; do
  if [ -e "$RUN/ok" ]; then
    if [ "$PHASE" = live ]; then
      if nix-env -p "$PROFILE" --set "$NEW" && "$NEW/bin/switch-to-configuration" boot; then
        printf 'PHASE=boot\nOLD=%s\nNEW=%s\nMODE=%s\n' "$OLD" "$NEW" "$MODE" > "$STATE/trial"
        result "live-ok mode=$MODE (осталась проверка первой перезагрузки)"
      else
        rm -f "$STATE/trial"
        result "live-ok-not-saved mode=$MODE (не удалось записать загрузчик; после перезагрузки вернётся прежняя система)"
      fi
    else
      rm -f "$STATE/trial"
      result "ok mode=$MODE"
    fi
    exit 0
  fi
  if [ -e "$RUN/fail" ]; then
    fail "оболочка: $(head -c 300 "$RUN/fail" 2>/dev/null)"
  fi
  if [ "$t" -ge 20 ] && systemctl is-failed --quiet display-manager.service; then
    fail "экран входа не запустился (display-manager failed)"
  fi
  sleep 3
  t=$((t + 3))
done
fail "за $LIMIT с никто не вошёл в сеанс niri либо панель задач не появилась"
