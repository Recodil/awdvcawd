# win11-zapret-root - смена настроек zapret без пересборки системы (запускается через sudo).
#   win11-zapret-root set config|fake|game ЗНАЧЕНИЕ   запомнить и перезапустить службу
#   win11-zapret-root reset                           забыть выбор: как собрано в системе
# Пользователям группы wheel пароль не нужен, поэтому значения проверяются строго.
export PATH="/run/current-system/sw/bin:$PATH"
UNIT=zapret-discord-youtube.service
CHOICE=/var/lib/win11-zapret
[ "$(id -u)" -eq 0 ] || { echo "нужен sudo" >&2; exit 1; }

store="$(systemctl show -p Environment --value "$UNIT" | tr ' ' '\n' | sed -n 's/^ZAPRET_BASE=//p' | head -n 1)"
[ -d "$store/configs" ] || { echo "служба zapret не найдена" >&2; exit 1; }

case "${1:-}" in
  set)
    kind="${2:-}"; value="${3:-}"
    case "$kind" in
      config) case "$value" in ""|*/*|.*) echo "недопустимое имя" >&2; exit 1 ;; esac
              [ -f "$store/configs/$value" ] || { echo "нет стратегии \"$value\"" >&2; exit 1; } ;;
      fake)   case "$value" in default) ;; */*|*[!A-Za-z0-9._-]*|.*) echo "недопустимое имя" >&2; exit 1 ;;
                *.bin) [ -f "$store/files/fake/$value" ] || { echo "нет файла \"$value\"" >&2; exit 1; } ;;
                *) echo "недопустимое имя" >&2; exit 1 ;; esac ;;
      game)   case "$value" in off|udp|tcp|all) ;; *) echo "off, udp, tcp или all" >&2; exit 1 ;; esac ;;
      *) echo "config, fake или game" >&2; exit 1 ;;
    esac
    mkdir -p "$CHOICE" && printf '%s\n' "$value" > "$CHOICE/$kind" || exit 1
    systemctl restart "$UNIT" ;;
  reset) rm -rf "$CHOICE"; systemctl restart "$UNIT" ;;
  *) sed -n '1,3p' "$0" | sed 's/^# \{0,1\}//' ;;
esac
