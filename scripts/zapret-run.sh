# Запуск службы zapret со стратегией, выбранной без пересборки системы.
# Выбор лежит в /var/lib/win11-zapret (файлы config, fake, game); его пишет win11-zapret-root.
# Набор zapret из /nix/store менять нельзя, поэтому он копируется в /run и правится там.
# Если выбора нет или копия не удалась, служба запускается как собрана.
store="${ZAPRET_BASE:?}"
work="${WIN11_ZAPRET_WORK:-/run/win11-zapret}"      # другие пути нужны только для проверки сценария
run="$work/zapret"
choice="${WIN11_ZAPRET_CHOICE:-/var/lib/win11-zapret}"

pick() { [ -s "$choice/$1" ] && head -n 1 "$choice/$1"; }

prepare() {
  local name fake game
  name="$(pick config)"; fake="$(pick fake)"; game="$(pick game)"
  [ -n "$name$fake$game" ] || return 1
  rm -rf "$work"; mkdir -p "$work" || return 1
  cp -a "$store" "$run" && chmod -R u+rwX "$run" || return 1
  # пути внутри сценариев и настроек ведут в /nix/store - переводим на копию (двоичные файлы не трогаем)
  grep -rlIZ -- "$store" "$run" | xargs -0 -r sed -i "s|$store|$run|g"
  if [ -n "$name" ]; then
    if [ -f "$run/configs/$name" ]; then cp -f "$run/configs/$name" "$run/config"
    else echo "win11-zapret: стратегии \"$name\" нет в наборе, остаётся собранная"; fi
  fi
  case "$fake" in
    ""|default|*/*) ;;
    *) [ -f "$run/files/fake/$fake" ] && cp -f "$run/files/fake/$fake" "$run/files/fake/ACTIVE_DISCORD_UDP.bin" ;;
  esac
  case "$game" in
    off) rm -f "$run/hostlists/.game_filter.enabled" ;;
    udp|tcp|all) echo "$game" > "$run/hostlists/.game_filter.enabled" ;;
  esac
  [ -x "$run/init.d/sysv/zapret" ]
}

case "${1:-}" in
  start)
    if prepare; then
      export ZAPRET_BASE="$run"
      exec "$run/init.d/sysv/zapret" start
    fi
    rm -rf "$work"
    exec "$store/init.d/sysv/zapret" start ;;
  stop)
    if [ -x "$run/init.d/sysv/zapret" ]; then ZAPRET_BASE="$run" "$run/init.d/sysv/zapret" stop; fi
    exec "$store/init.d/sysv/zapret" stop ;;
  restart) "$0" stop; exec "$0" start ;;
  *) echo "start | stop | restart" >&2; exit 1 ;;
esac
