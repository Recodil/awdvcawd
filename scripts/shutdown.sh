# win11-shutdown - команда shutdown с параметрами как в Windows.
#   shutdown /s            выключить через 30 секунд
#   shutdown /r /t 500     перезагрузить через 500 секунд
#   shutdown /a            отменить запланированное
#   shutdown /l            выйти из системы        /h  гибернация      /p  выключить сразу
#   /t СЕК  задержка       /c "текст"  пояснение в сообщении       /f  принимается, ничего не меняет
# Параметры в стиле Linux (shutdown -h now, shutdown -r +5) передаются настоящему shutdown.
export PATH="$PATH:/run/current-system/sw/bin"
UNIT=win11-shutdown
STATE="${XDG_RUNTIME_DIR:-/tmp}/win11-shell"
mkdir -p "$STATE" 2>/dev/null

usage() {
  cat <<'EOF'
Использование: shutdown [/s | /r | /l | /h | /p | /a] [/t сек] [/c "комментарий"] [/f]

    /s    Завершение работы компьютера.
    /r    Полное завершение работы и перезагрузка компьютера.
    /l    Завершение сеанса (выход из системы).
    /h    Переход в режим гибернации.
    /p    Немедленное отключение компьютера без задержки и предупреждения.
    /a    Отмена завершения работы системы.
    /t xxx  Задержка перед завершением работы в секундах (по умолчанию 30).
    /c "комментарий"  Пояснение, которое будет показано в сообщении.
    /f    Принудительное закрытие программ (здесь программы закрываются всегда).

Примеры:  shutdown /r /t 500      shutdown /s /t 0      shutdown /a
EOF
}

win=0
for a in "$@"; do case "$a" in /*) win=1 ;; esac; done
if [ "$#" -eq 0 ]; then usage; exit 0; fi
if [ "$win" -eq 0 ]; then
  real=/run/current-system/sw/bin/shutdown
  [ -x "$real" ] || { echo "Не найдена системная команда shutdown." >&2; exit 1; }
  exec "$real" "$@"
fi

action=""; delay=""; comment=""
while [ "$#" -gt 0 ]; do
  a="$(printf '%s' "$1" | tr 'A-Z' 'a-z')"
  case "$a" in
    /s|/sg) action=poweroff ;;
    /r|/g) action=reboot ;;
    /l) action=logout ;;
    /h) action=hibernate ;;
    /p) action=poweroff; delay=0 ;;
    /a) action=abort ;;
    /f|/hybrid|/soft|/fw|/e|/o) ;;
    /t) shift; delay="${1:-}" ;;
    /t:*) delay="${a#/t:}" ;;
    /c) shift; comment="${1:-}" ;;
    /d|/m) shift ;;
    '/?'|/help) usage; exit 0 ;;
    *) echo "Недопустимый параметр: $1" >&2; echo >&2; usage >&2; exit 1 ;;
  esac
  shift
done
[ -n "$action" ] || { usage; exit 1; }

say() {   # заголовок, текст, можно ли отменить
  qs -p /etc/win11-shell ipc call shell notice "$1" "$2" "$3" >/dev/null 2>&1 \
    || notify-send -a "Система" "$1" "$2" 2>/dev/null || true
}
pending() { systemctl --user is-active --quiet "$UNIT.timer" 2>/dev/null; }

case "$action" in
  abort)
    if pending; then
      systemctl --user stop "$UNIT.timer" 2>/dev/null
      rm -f "$STATE/shutdown"
      qs -p /etc/win11-shell ipc call shell noticeClose >/dev/null 2>&1
      notify-send -a "Система" "Выход из системы отменён" "Запланированное завершение работы отменено." 2>/dev/null
      exit 0
    fi
    echo "Не удаётся прервать завершение работы системы, так как завершение не выполняется.(1116)" >&2
    exit 1 ;;
  logout)
    qs -p /etc/win11-shell ipc call shell logout >/dev/null 2>&1 || niri msg action quit --skip-confirmation
    exit 0 ;;
  hibernate)
    exec systemctl hibernate ;;
esac

[ -n "$delay" ] || delay=30
case "$delay" in ''|*[!0-9]*) echo "Недопустимое значение задержки: $delay" >&2; exit 1 ;; esac
[ "$delay" -le 315360000 ] || { echo "Задержка не может быть больше 315360000 секунд (10 лет)." >&2; exit 1; }
if pending; then
  echo "Завершение работы системы уже запланировано.(1190)" >&2
  exit 1
fi

if [ "$delay" -eq 0 ]; then
  # сразу: с экраном "Завершение работы", как из меню "Пуск"
  qs -p /etc/win11-shell ipc call shell "$action" >/dev/null 2>&1 || systemctl "$action"
  exit 0
fi

systemctl --user reset-failed "$UNIT.timer" "$UNIT.service" >/dev/null 2>&1
if ! systemd-run --user --quiet --unit="$UNIT" --on-active="${delay}s" --timer-property=AccuracySec=1s \
       /run/current-system/sw/bin/systemctl "$action"; then
  echo "Не удалось запланировать завершение работы." >&2
  exit 1
fi
printf '%s %s\n' "$action" "$(( $(date +%s) + delay ))" > "$STATE/shutdown"

if [ "$delay" -lt 60 ]; then left="менее чем через минуту"
elif [ "$delay" -lt 7200 ]; then left="через $(( (delay + 30) / 60 )) мин"
else left="через $(( (delay + 1800) / 3600 )) ч"; fi
if [ "$action" = reboot ]; then what="Компьютер будет перезагружен"; else what="Работа компьютера будет завершена"; fi
when="$(date -d "@$(( $(date +%s) + delay ))" '+%d.%m.%Y %H:%M:%S' 2>/dev/null)"
body="$what $left."
[ -n "$when" ] && body="$body
Завершение работы запланировано на $when."
[ -n "$comment" ] && body="$body

$comment"
say "Ваш сеанс будет завершён" "$body" "1"
exit 0
