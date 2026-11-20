# win11-zapret - обход замедления YouTube и Discord (Zapret 2 от bol-van / nfqws2).
#   win11-zapret            состояние и быстрая проверка
#   win11-zapret check      проверка сайтов (YouTube, Discord и др.); код возврата - число сбоев
#   win11-zapret test       подбор стратегии под вашего провайдера (долго, нужен sudo)
#   win11-zapret list       список стратегий
#   win11-zapret set НОМЕР  выбрать стратегию по номеру из списка (или по имени) и применить
#   win11-zapret fake [ИМЯ] подставной пакет для звонков Discord (без имени - список)
#   win11-zapret game off|udp|tcp|all   игровой фильтр: обход для всех портов выше 1024
#   win11-zapret calls      перебор стратегий во время звонка Discord, пока он не соединится
#   win11-zapret voice      что делать, если звонок Discord висит на "RTC connecting"
#   win11-zapret off | on   выключить / включить до перезагрузки
#   win11-zapret disable | enable   выключить / включить насовсем (пересборка системы)
export PATH="$PATH:/run/current-system/sw/bin:/run/wrappers/bin"
KIT=/etc/nixos/win11-shell
UNIT=zapret-discord-youtube.service
red() { printf '\033[31m%s\033[0m\n' "$*"; }
grn() { printf '\033[32m%s\033[0m\n' "$*"; }

configs_dir() {
  local b; b="$(readlink -f "$(command -v zapret-service 2>/dev/null)" 2>/dev/null)"
  [ -n "$b" ] && echo "${b%/bin/*}/opt/zapret/configs"
}
fakes_dir() { local d; d="$(configs_dir)"; [ -n "$d" ] && echo "${d%/configs}/files/fake"; }
# Выбор, сделанный без пересборки (/var/lib/win11-zapret), важнее того, с чем система собрана.
CHOICE=/var/lib/win11-zapret
setting() {
  local kind="${1#zapret-}"
  if [ -s "$CHOICE/$kind" ]; then head -n 1 "$CHOICE/$kind"
  elif [ -f "$KIT/$1" ]; then cat "$KIT/$1"; else echo "$2"; fi
}
current_fake() { setting zapret-fake quic_initial_lemana_pro.bin; }
# Служба умеет менять настройки на ходу (появилось в версии 2026.11.15)?
live() { command -v win11-zapret-root >/dev/null && systemctl cat "$UNIT" 2>/dev/null | grep -q win11-zapret-run; }
# apply вид значение: на ходу, а на старой сборке - через пересборку системы
apply() {
  if live; then
    sudo -n win11-zapret-root set "$1" "$2" 2>/dev/null || sudo win11-zapret-root set "$1" "$2"
  else
    printf '%s\n' "$2" | sudo tee "$KIT/zapret-$1" >/dev/null || return 1
    echo "эта сборка системы ещё не умеет менять настройки на ходу - пересобираю"
    rebuild
  fi
}
# Счётчики правил брандмауэра: видно, доходят ли пакеты звонка до zapret.
udp_counters() {
  sudo iptables -t mangle -nvL POSTROUTING 2>/dev/null | awk '/NFQUEUE/ && /udp/ { printf "  пакетов: %s   %s\n", $1, $0 }' | cut -c1-150
}
current() { setting zapret-config general; }

status() {
  if [ -e "$KIT/no-zapret" ]; then red "zapret выключен насовсем (win11-zapret enable - включить)"; return 1; fi
  if ! command -v zapret-service >/dev/null; then red "zapret не установлен: выполните win11-update"; return 1; fi
  echo "ядро: Zapret 2 (bol-van / nfqws2)"
  echo "стратегия: $(current)"
  echo "пакет для звонков Discord: $(current_fake)"
  echo "игровой фильтр: $(setting zapret-game off)"
  if systemctl is-active --quiet "$UNIT"; then grn "служба работает"
  else red "служба не работает: sudo systemctl status $UNIT"; return 1; fi
}

# Одна проверка: имя, адрес. Успех - сервер ответил по HTTPS за 6 секунд (код ответа не важен).
probe() {
  local code
  code="$(curl -s -o /dev/null -m 6 --connect-timeout 4 -w '%{http_code}' "$2" 2>/dev/null)"
  if [ -n "$code" ] && [ "$code" != "000" ]; then printf '  %-22s ' "$1"; grn "работает ($code)"; return 0
  else printf '  %-22s ' "$1"; red "НЕТ ОТВЕТА"; return 1; fi
}
check() {
  local bad=0
  echo "Контроль (должно работать всегда):"
  probe "Яндекс" https://ya.ru || { red "  нет интернета вообще - проверка не имеет смысла"; return 99; }
  echo "YouTube:"
  probe "youtube.com" https://www.youtube.com || bad=$((bad + 1))
  probe "картинки (ytimg)" https://i.ytimg.com/generate_204 || bad=$((bad + 1))
  probe "видео (googlevideo)" https://redirector.googlevideo.com || bad=$((bad + 1))
  echo "Discord:"
  probe "discord.com" https://discord.com || bad=$((bad + 1))
  probe "gateway.discord.gg" https://gateway.discord.gg || bad=$((bad + 1))
  probe "cdn.discordapp.com" https://cdn.discordapp.com || bad=$((bad + 1))
  probe "updates.discord.com" https://updates.discord.com || bad=$((bad + 1))
  echo
  if [ "$bad" -eq 0 ]; then grn "Все проверки пройдены."
  else red "Не прошло проверок: $bad. Подберите другую стратегию: win11-zapret test"; fi
  return "$bad"
}

names() { find "$1" -maxdepth 1 -type f ! -name 'config.base' -printf '%f\n' | sort; }
# Имена стратегий содержат скобки и пробелы, которые в терминале приходится брать в кавычки.
# Поэтому стратегию можно назвать номером из списка или коротко: alt3, "simple fake alt", fake_tls_auto.
squash() { printf '%s' "$1" | tr 'A-Z' 'a-z' | tr -cd 'a-z0-9'; }
resolve() {   # каталог, что ввёл пользователь -> точное имя
  local d="$1" want="$2" n key
  [ -f "$d/$want" ] && { printf '%s\n' "$want"; return 0; }
  case "$want" in
    *[!0-9]*) ;;
    *) n="$(names "$d" | sed -n "${want}p")"; [ -n "$n" ] && { printf '%s\n' "$n"; return 0; }; return 1 ;;
  esac
  key="$(squash "$want")"; key="${key#general}"
  names "$d" | while IFS= read -r n; do
    k="$(squash "$n")"; [ "${k#general}" = "$key" ] && { printf '%s\n' "$n"; break; }
  done | grep .
}

# Состояние для "Параметров": строки "ключ<TAB>значение".
state() {
  local d
  if [ -e "$KIT/no-zapret" ]; then printf 'mode\tdisabled\n'
  elif ! command -v zapret-service >/dev/null; then printf 'mode\tmissing\n'
  elif systemctl is-active --quiet "$UNIT"; then printf 'mode\ton\n'
  else printf 'mode\toff\n'; fi
  printf 'current\t%s\n' "$(current)"
  printf 'fake\t%s\n' "$(current_fake)"
  printf 'game\t%s\n' "$(setting zapret-game off)"
  printf 'live\t%s\n' "$(live && echo 1 || echo 0)"
  d="$(configs_dir)"; [ -d "$d" ] && names "$d" | sed 's/^/strategy\t/'
  d="$(fakes_dir)"; [ -d "$d" ] && find "$d" -maxdepth 1 -name 'quic_initial_*.bin' -printf 'fakefile\t%f\n' | sort
}

rebuild() {
  if command -v win11-update >/dev/null; then win11-update
  else red "нет win11-update - пересоберите систему: sudo nixos-rebuild switch"; fi
}

case "${1:-}" in
  ""|status) status; echo; check ;;
  state) state ;;
  check) check ;;
  list)
    d="$(configs_dir)"; [ -d "$d" ] || { red "zapret не установлен"; exit 1; }
    cur="$(current)"
    names "$d" | awk -v cur="$cur" '{ printf "%s %2d  %s\n", ($0 == cur ? "*" : " "), NR, $0 }'
    echo
    echo "Выбрать по номеру: win11-zapret set 2   (или по короткому имени: win11-zapret set alt3)" ;;
  set)
    name="${2:-}"; d="$(configs_dir)"
    [ -d "$d" ] || { red "zapret не установлен"; exit 1; }
    [ -n "$name" ] || { red "укажите номер из списка: win11-zapret list"; exit 1; }
    name="$(resolve "$d" "$name")" || { red "нет такой стратегии. Список: win11-zapret list"; exit 1; }
    echo "стратегия \"$name\", применяю…"
    apply config "$name" && sleep 3 && check ;;
  fake)
    name="${2:-}"; d="$(fakes_dir)"; cur="$(current_fake)"
    if [ -z "$name" ]; then
      echo "Сейчас: $cur"
      echo "Доступные (звонкам обычно подходят quic_initial_*):"
      if [ -d "$d" ]; then
        find "$d" -maxdepth 1 -name '*.bin' ! -name 'ACTIVE_*' -printf '%f\n' | sort | sed 's/^/  /'
      fi
      echo "  default   (тот, что выбрал Flowseal)"
      echo "Выбрать: win11-zapret fake quic_initial_lemana_pro.bin"
      exit 0
    fi
    case "$name" in default) ;; */*|*[!A-Za-z0-9._-]*) red "недопустимое имя"; exit 1 ;; *.bin) ;; *) name="$name.bin" ;; esac
    if [ "$name" != default ] && [ -d "$d" ] && [ ! -f "$d/$name" ]; then
      red "нет файла \"$name\". Список: win11-zapret fake"; exit 1
    fi
    apply fake "$name" && echo "пакет для звонков: $name" ;;
  game)
    case "${2:-}" in
      off|udp|tcp|all) apply game "$2" && echo "игровой фильтр: $2" ;;
      *) echo "игровой фильтр: $(setting zapret-game off)"; echo "изменить: win11-zapret game off|udp|tcp|all" ;;
    esac ;;
  calls)
    d="$(configs_dir)"; [ -d "$d" ] || { red "zapret не установлен"; exit 1; }
    live || { red "нужна новая сборка системы: выполните win11-update и повторите"; exit 1; }
    was="$(current)"; was_fake="$(current_fake)"
    cat <<'EOF'
Перебор для звонков Discord. Зайдите в голосовой канал и оставьте его открытым:
пока там "RTC connecting", Discord сам пробует соединиться заново.
После каждой смены подождите секунд 15-20 и ответьте:
  д  - звонок соединился, оставить так      Enter - не соединился, дальше      в - выйти
EOF
    ask() {   # что пробуем -> 0: подошло, 1: дальше, 2: выход
      printf '%s  Соединился? [д/Enter/в] ' "$1"; read -r ans
      case "$ans" in д|Д|y|Y|l|L) return 0 ;; в|В|q|Q) return 2 ;; *) return 1 ;; esac
    }
    echo; echo "Круг 1: игровой фильтр UDP (звонок может идти мимо обычных портов)"
    if [ "$(setting zapret-game off)" = off ]; then
      apply game udp; ask "  игровой фильтр udp."; r=$?
      [ "$r" -eq 0 ] && { grn "Оставлено: игровой фильтр udp."; exit 0; }
      [ "$r" -eq 2 ] && { apply game off; exit 0; }
    else echo "  уже включён"; fi
    echo; echo "Круг 2: подставные пакеты (стратегия \"$was\")"
    f="$(fakes_dir)"
    for name in $(find "$f" -maxdepth 1 -name 'quic_initial_*.bin' -printf '%f\n' 2>/dev/null | sort) stun.bin; do
      [ "$name" = "$was_fake" ] && continue
      [ -f "$f/$name" ] || continue
      apply fake "$name" || continue
      ask "  пакет $name."; r=$?
      [ "$r" -eq 0 ] && { grn "Оставлено: пакет $name."; exit 0; }
      [ "$r" -eq 2 ] && { apply fake "$was_fake"; exit 0; }
    done
    apply fake "$was_fake"
    echo; echo "Круг 3: стратегии"
    total="$(names "$d" | wc -l)"; n=0
    while IFS= read -r name <&3; do
      n=$((n + 1)); [ "$name" = "$was" ] && continue
      apply config "$name" || continue
      ask "  $n из $total: $name."; r=$?
      [ "$r" -eq 0 ] && { grn "Оставлено: стратегия \"$name\"."; echo "Проверьте и сайты: win11-zapret check"; exit 0; }
      [ "$r" -eq 2 ] && break
    done 3< <(names "$d")
    apply config "$was"
    red "Ничего не подошло, возвращено как было."
    echo "Пришлите разработчику вывод команды: win11-zapret voice" ;;
  voice)
    status
    echo
    echo "Правила для UDP (звонки идут через порты 50000-50100 и 19294-19344):"
    out="$(udp_counters)"
    if [ -n "$out" ]; then echo "$out"; else red "  правил для UDP нет - служба не настроила брандмауэр"; fi
    cat <<'EOF'

Если звонок висит на "RTC connecting", пробуйте по порядку, после каждого шага - звонок заново:
  1. Позвоните и снова выполните win11-zapret voice. Число пакетов не растёт -
     звонок идёт мимо zapret: включите игровой фильтр, win11-zapret game udp
  2. Перебор во время звонка, без пересборок: win11-zapret calls
  3. Вручную: win11-zapret fake ИМЯ, win11-zapret set НОМЕР
  4. В Discord: настройки канала - регион - любой, кроме "Автоматически"
EOF
    ;;
  test)
    command -v zapret-test-strategies >/dev/null || { red "нет zapret-test-strategies: выполните win11-update"; exit 1; }
    echo "Подбор перебирает стратегии по очереди; на это время обход отключается."
    echo "В конце выберите лучшую по таблице и примените: win11-zapret set \"ИМЯ\""
    echo "Журналы: /var/log/zapret-discord-youtube-test"
    sudo zapret-test-strategies ;;
  off) sudo systemctl stop "$UNIT" && echo "выключено до перезагрузки" ;;
  on) sudo systemctl start "$UNIT" && status ;;
  disable) sudo touch "$KIT/no-zapret" && rebuild ;;
  enable) sudo rm -f "$KIT/no-zapret" && rebuild ;;
  *) sed -n '1,12p' "$0" | sed 's/^# \{0,1\}//' ;;
esac
