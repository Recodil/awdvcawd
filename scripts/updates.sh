# win11-updates - центр обновления: оболочка, NixOS, программы, драйверы, прошивки.
#   win11-updates check             что можно обновить: раздел<TAB>состояние<TAB>id<TAB>название<TAB>пояснение
#   win11-updates apply РАЗДЕЛ [..]  установить в отдельном окне:
#        shell [архив] | nixos | release ВЫПУСК | apps | drivers | firmware | all
#        queue ПУНКТ...   несколько разделов одним заходом; пункт - "раздел" или "раздел=параметр"
# Разделы: shell, nixos, release, apps, driver, firmware. Состояния: update - есть обновление,
# ok - обновлять нечего, info - справка, install/applied/none - см. win11-drivers.
export PATH="$PATH:/run/current-system/sw/bin"
export LC_ALL=C.UTF-8
KIT=/etc/nixos/win11-shell-kit
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/win11-shell"
CHANNELS=https://channels.nixos.org
T="$(printf '\t')"
mkdir -p "$STATE"

row() { printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5"; }
online() { curl -fsI -m 8 -o /dev/null "$CHANNELS" 2>/dev/null; }

nixos_current() { nixos-version 2>/dev/null | cut -d' ' -f1; }
# выпуск установленной системы: 25.05; для нестабильной ветки - unstable
nixos_release() {
  local v; v="$(nixos_current)"
  case "$v" in *pre*) echo unstable ;; *) printf '%s\n' "$v" | cut -d. -f1,2 ;; esac
}
# последняя сборка канала: 25.05.805252.b43c397f6c21
channel_head() {
  curl -fsSIL -m 12 -o /dev/null -w '%{url_effective}' "$CHANNELS/nixos-$1" 2>/dev/null | sed 's|.*/nixos-||'
}
next_release() {
  local y="${1%%.*}" m="${1##*.}"
  if [ "$m" = 05 ]; then echo "$y.11"; else echo "$((y + 1)).05"; fi
}

check_shell() {
  local found=0 st f date
  while IFS="$T" read -r st f date; do
    [ "$st" = new ] || continue
    found=1; row shell update "$f" "Оболочка: ${f##*/}" "скачан $date"
  done < <(win11-updater find 2>/dev/null)
  [ "$found" -eq 1 ] && return
  # GitHub: в файле scripts/repo записано "владелец/репозиторий"; сравниваются номера версий
  local repo="" mine="" theirs=""
  for rf in "$KIT/scripts/repo" "/etc/nixos/win11-shell/scripts/repo"; do
    [ -f "$rf" ] && repo="$(tr -d ' \t\r\n' < "$rf" 2>/dev/null)" && [ -n "$repo" ] && break
  done
  for vf in "$KIT/scripts/version" "/etc/nixos/win11-shell/scripts/version"; do
    [ -f "$vf" ] && mine="$(cat "$vf" 2>/dev/null)" && [ -n "$mine" ] && break
  done
  if [ -n "$repo" ]; then
    theirs="$(curl -fsL -m 10 "https://raw.githubusercontent.com/$repo/main/scripts/version" 2>/dev/null | head -n 1 | tr -cd '0-9.-')"
    if [ -n "$theirs" ] && [ "$theirs" != "$mine" ] \
       && [ "$(printf '%s\n%s\n' "$mine" "$theirs" | sort -V | tail -n 1)" = "$theirs" ]; then
      row shell update github "Оболочка: версия $theirs" "на GitHub ($repo); установлена ${mine:-?}"
      return
    fi
  fi
  date="$(date -r "$KIT/install.sh" '+%d.%m.%Y' 2>/dev/null)"
  row shell ok - "Оболочка" "установлена версия ${mine:-от ${date:-?}}$([ -n "$repo" ] && echo "; обновления: github.com/$repo")"
}

check_nixos() {
  local cur rel next
  cur="$(nixos_current)"; rel="$(nixos_release)"
  [ -n "$cur" ] || { row nixos info - "NixOS" "не удалось узнать версию системы"; return; }
  if ! online; then row nixos info - "NixOS $cur" "нет связи с сервером обновлений"; return; fi

  # Проверяем ТОЛЬКО глобальные обновления (новый релиз, e.g. 24.11 -> 25.05)
  # Мелкие промежуточные коммиты канала скрыты, чтобы не спамить ежедневными уведомлениями
  if [ "$rel" != unstable ]; then
    next="$(next_release "$rel")"
    if curl -fsI -m 8 -o /dev/null "$CHANNELS/nixos-$next" 2>/dev/null; then
      row release update "$next" "Глобальное обновление: NixOS $next" "доступен новый выпуск (переход с $rel)"
      return
    fi
  fi
  row nixos ok - "NixOS $rel" "актуальный глобальный выпуск ($cur)"
}

check_apps() {
  local fp=0 nix=0
  if command -v flatpak >/dev/null 2>&1; then
    fp="$( { flatpak remote-ls --user --updates --app --columns=application 2>/dev/null
             flatpak remote-ls --system --updates --app --columns=application 2>/dev/null; } | grep -c . )"
  fi
  nix="$(nix-env -q 2>/dev/null | grep -c .)"
  if [ "$fp" -gt 0 ]; then row apps update - "Программы" "Flathub: обновлений - $fp; из NixOS установлено - $nix"
  elif [ "$nix" -gt 0 ]; then row apps info - "Программы" "из NixOS установлено - $nix: проверяются при обновлении"
  else row apps ok - "Программы" "обновлять нечего"; fi
}

check_drivers() {
  local id class dev drv st note src
  local cmd="win11-drivers"
  command -v win11-drivers >/dev/null 2>&1 || [ ! -x "$(dirname "$0")/drivers.sh" ] || cmd="$(dirname "$0")/drivers.sh"
  while IFS="$T" read -r id class dev drv st note src; do
    [ -n "$id" ] || continue
    local hint="драйвер: ${drv:-нет}"
    [ -n "$note" ] && hint="$hint — $note"
    [ -n "$src" ] && hint="[$src] $hint"
    row driver "$st" "$id" "$class: $dev" "$hint"
  done < <($cmd detect 2>/dev/null)
}

# необязательное: свежее ядро, новый драйвер NVIDIA, полный набор прошивок
check_optional() {
  local name st title note
  local cmd="win11-drivers"
  command -v win11-drivers >/dev/null 2>&1 || [ ! -x "$(dirname "$0")/drivers.sh" ] || cmd="$(dirname "$0")/drivers.sh"
  while IFS="$T" read -r name st title note; do
    [ -n "$name" ] && row optional "$st" "$name" "$title" "$note"
  done < <($cmd optional 2>/dev/null)
}

check_firmware() {
  command -v fwupdmgr >/dev/null 2>&1 || return 0
  local out n
  out="$(timeout 25 fwupdmgr get-updates 2>/dev/null)"
  n="$(printf '%s\n' "$out" | grep -ciE 'new version|новая версия')"
  if [ "$n" -gt 0 ]; then row firmware update - "Прошивки устройств" "обновлений - $n (BIOS, накопители, док-станции)"
  else row firmware ok - "Прошивки устройств" "обновлять нечего"; fi
}

# ---- установка (выполняется внутри окна терминала) ----
show_logo() {
  [ -n "${WIN11_LOGO_SHOWN:-}" ] && return 0
  export WIN11_LOGO_SHOWN=1
  cat << "LOGO"
         [1;34m?[0m[1;34m?[0m[1;34m#[0m     [1;36m&[0m[1;36m&[0m[1;36m@[0m[1;36m/[0m[1;36m&[0m    [1;36m&[0m[1;36m@[0m[1;36m/[0m
        [1;34m?[0m[1;34m#[0m[1;34m\[0m[1;34m?[0m[1;34m?[0m[1;34m#[0m    [1;36m/[0m[1;36m&[0m[1;36m&[0m[1;36m@[0m[1;36m/[0m [1;36m&[0m[1;36m@[0m[1;36m/[0m[1;36m&[0m[1;36m&[0m[1;36m@[0m
         [1;34m?[0m[1;34m?[0m[1;34m#[0m[1;34m\[0m[1;34m?[0m[1;34m?[0m    [1;36m@[0m[1;36m/[0m[1;36m&[0m[1;36m&[0m[1;36m@[0m[1;36m/[0m[1;36m&[0m[1;36m&[0m[1;36m@[0m[1;36m/[0m
     [1;34m#[0m[1;34m\[0m[1;34m?[0m[1;34m?[0m[1;34m#[0m[1;34m\[0m[1;34m?[0m[1;34m?[0m[1;34m#[0m[1;34m\[0m[1;34m?[0m[1;34m?[0m[1;34m#[0m[1;34m\[0m[1;34m?[0m[1;34m?[0m[1;36m@[0m[1;36m/[0m[1;36m&[0m[1;36m&[0m[1;36m@[0m[1;36m/[0m     [1;34m?[0m
    [1;34m\[0m[1;34m?[0m[1;34m?[0m[1;34m#[0m[1;34m\[0m[1;34m?[0m[1;34m?[0m[1;34m#[0m[1;34m\[0m[1;34m?[0m[1;34m?[0m[1;34m#[0m[1;34m\[0m[1;34m?[0m[1;34m?[0m[1;34m#[0m[1;34m\[0m[1;34m?[0m[1;36m&[0m[1;36m@[0m[1;36m/[0m[1;36m&[0m[1;36m&[0m    [1;34m#[0m[1;34m\[0m[1;34m?[0m
    [1;34m?[0m[1;34m#[0m[1;34m\[0m[1;34m?[0m[1;34m?[0m[1;34m#[0m[1;36m/[0m[1;36m&[0m[1;36m&[0m[1;36m@[0m[1;36m/[0m[1;34m?[0m[1;34m?[0m[1;34m#[0m[1;34m\[0m[1;34m?[0m[1;34m?[0m[1;34m#[0m [1;36m&[0m[1;36m&[0m[1;36m@[0m[1;36m/[0m[1;36m&[0m  [1;34m\[0m[1;34m?[0m[1;34m?[0m[1;34m#[0m[1;34m\[0m
         [1;36m&[0m[1;36m&[0m[1;36m@[0m[1;36m/[0m[1;36m&[0m          [1;36m/[0m[1;36m&[0m[1;36m&[0m[1;36m@[0m[1;36m/[0m[1;34m?[0m[1;34m?[0m[1;34m#[0m[1;34m\[0m[1;34m?[0m
 [1;36m@[0m[1;36m/[0m[1;36m&[0m[1;36m&[0m[1;36m@[0m[1;36m/[0m[1;36m&[0m[1;36m&[0m[1;36m@[0m[1;36m/[0m[1;36m&[0m[1;36m&[0m            [1;36m@[0m[1;36m/[0m[1;34m?[0m[1;34m?[0m[1;34m#[0m[1;34m\[0m[1;34m?[0m[1;34m?[0m[1;34m#[0m[1;34m\[0m[1;34m?[0m[1;34m?[0m
[1;36m/[0m[1;36m&[0m[1;36m&[0m[1;36m@[0m[1;36m/[0m[1;36m&[0m[1;36m&[0m[1;36m@[0m[1;36m/[0m[1;36m&[0m[1;36m&[0m[1;36m@[0m              [1;34m?[0m[1;34m#[0m[1;34m\[0m[1;34m?[0m[1;34m?[0m[1;34m#[0m[1;34m\[0m[1;34m?[0m[1;34m?[0m[1;34m#[0m[1;34m\[0m[1;34m?[0m
 [1;36m@[0m[1;36m/[0m[1;36m&[0m[1;36m&[0m[1;36m@[0m[1;36m/[0m[1;36m&[0m[1;36m&[0m[1;36m@[0m[1;34m\[0m[1;34m?[0m[1;34m?[0m            [1;34m#[0m[1;34m\[0m[1;34m?[0m[1;34m?[0m[1;34m#[0m[1;34m\[0m[1;34m?[0m[1;34m?[0m[1;34m#[0m[1;34m\[0m[1;34m?[0m[1;34m?[0m
    [1;36m/[0m[1;36m&[0m[1;36m&[0m[1;36m@[0m[1;36m/[0m[1;36m&[0m[1;34m?[0m[1;34m#[0m[1;34m\[0m[1;34m?[0m          [1;34m\[0m[1;34m?[0m[1;34m?[0m[1;34m#[0m[1;34m\[0m
   [1;36m&[0m[1;36m&[0m[1;36m@[0m[1;36m/[0m[1;36m&[0m  [1;34m\[0m[1;34m?[0m[1;34m?[0m[1;34m#[0m[1;34m\[0m[1;36m&[0m[1;36m&[0m[1;36m@[0m[1;36m/[0m[1;36m&[0m[1;36m&[0m[1;36m@[0m[1;36m/[0m[1;34m?[0m[1;34m?[0m[1;34m#[0m[1;34m\[0m[1;34m?[0m[1;36m&[0m[1;36m@[0m[1;36m/[0m[1;36m&[0m[1;36m&[0m[1;36m@[0m
    [1;36m/[0m[1;36m&[0m[1;36m&[0m    [1;34m#[0m[1;34m\[0m[1;34m?[0m[1;34m?[0m[1;34m#[0m[1;36m/[0m[1;36m&[0m[1;36m&[0m[1;36m@[0m[1;36m/[0m[1;36m&[0m[1;36m&[0m[1;36m@[0m[1;36m/[0m[1;36m&[0m[1;36m&[0m[1;36m@[0m[1;36m/[0m[1;36m&[0m[1;36m&[0m[1;36m@[0m[1;36m/[0m[1;36m&[0m
     [1;36m@[0m    [1;36m/[0m[1;34m?[0m[1;34m?[0m[1;34m#[0m[1;34m\[0m[1;34m?[0m[1;34m?[0m[1;36m@[0m[1;36m/[0m[1;36m&[0m[1;36m&[0m[1;36m@[0m[1;36m/[0m[1;36m&[0m[1;36m&[0m[1;36m@[0m[1;36m/[0m[1;36m&[0m[1;36m&[0m[1;36m@[0m[1;36m/[0m[1;36m&[0m[1;36m&[0m
         [1;36m&[0m[1;34m?[0m[1;34m#[0m[1;34m\[0m[1;34m?[0m[1;34m?[0m[1;34m#[0m[1;34m\[0m[1;34m?[0m[1;36m&[0m    [1;36m@[0m[1;36m/[0m[1;36m&[0m[1;36m&[0m[1;36m@[0m[1;36m/[0m
        [1;36m&[0m[1;34m#[0m[1;34m\[0m[1;34m?[0m[1;34m?[0m[1;36m@[0m [1;34m?[0m[1;34m?[0m[1;34m#[0m[1;34m\[0m[1;36m&[0m    [1;36m&[0m[1;36m@[0m[1;36m/[0m[1;36m&[0m[1;36m&[0m[1;36m@[0m
         [1;34m?[0m[1;34m?[0m[1;34m#[0m[1;36m/[0m   [1;34m\[0m[1;34m?[0m[1;34m?[0m[1;34m#[0m[1;36m/[0m     [1;36m&[0m[1;36m@[0m[1;36m/[0m

  [1;37mЦентр обновления[0m [1;36mnixOS[0m [1;34m*[0m [1;36m2026[0m
LOGO
  echo
}
step() { echo; echo "== $1 =="; }

do_shell()    { if [ -n "${1:-}" ]; then win11-update "$1"; else win11-update; fi; }
do_nixos()    { win11-update --system; }
do_apps() {
  local log="${XDG_CACHE_HOME:-$HOME/.cache}/win11-shell/update.log"
  echo -e "\033[1;36mОбновление программ... Пожалуйста, подождите.\033[0m"
  if win11-pkg upgrade >> "$log" 2>&1; then
    echo -e "\033[1;32mПрограммы успешно обновлены\033[0m"
  else
    echo -e "\033[1;31mОшибка при обновлении программ. Подробности: $log\033[0m"
    return 1
  fi
}
do_drivers()  {
  local log="${XDG_CACHE_HOME:-$HOME/.cache}/win11-shell/update.log"
  echo -e "\033[1;36mПоиск и установка всех драйверов из источников NixOS... Пожалуйста, подождите.\033[0m"
  if win11-drivers apply >> "$log" 2>&1; then
    echo -e "\033[1;32mВсе подобранные драйверы успешно установлены\033[0m"
  else
    echo -e "\033[1;31mОшибка установки драйверов. Подробности: $log\033[0m"
    return 1
  fi
}
do_driver_single() {
  local feat="$1"
  local log="${XDG_CACHE_HOME:-$HOME/.cache}/win11-shell/update.log"
  echo -e "\033[1;36mПоиск и установка драйвера [$feat] из источников NixOS...\033[0m"
  if win11-drivers install "$feat" >> "$log" 2>&1; then
    echo -e "\033[1;32mДрайвер [$feat] успешно установлен и настроен\033[0m"
  else
    echo -e "\033[1;31mОшибка установки драйвера [$feat]. Подробности: $log\033[0m"
    return 1
  fi
}
do_firmware() {
  local log="${XDG_CACHE_HOME:-$HOME/.cache}/win11-shell/update.log"
  echo -e "\033[1;36mОбновление прошивок устройств... Пожалуйста, подождите.\033[0m"
  fwupdmgr refresh --force >> "$log" 2>&1 || true
  if fwupdmgr update -y >> "$log" 2>&1; then
    echo -e "\033[1;32mПрошивки успешно обновлены\033[0m"
  else
    echo -e "\033[1;31mОшибка обновления прошивок. Подробности: $log\033[0m"
    return 1
  fi
}
do_release() {
  local next="$1" old
  printf '%s' "$next" | grep -qE '^[0-9]{2}\.(05|11)$' || { echo "Неверный выпуск: $next"; return 1; }
  step "Переход на NixOS $next"
  echo "Система будет собрана заново из пакетов нового выпуска. Если сборка не пройдёт"
  echo "проверку, канал вернётся на прежний и система останется как была."
  printf 'Продолжить? [y/N] '; read -r ans
  case "$ans" in y|Y|д|Д) ;; *) echo "Отменено."; return 1 ;; esac
  old="$(sudo nix-channel --list | awk '$1 == "nixos" { print $2 }')"
  sudo nix-channel --add "$CHANNELS/nixos-$next" nixos || return 1
  if win11-update --system; then return 0; fi
  echo "Не получилось - возвращаю прежний канал."
  [ -n "$old" ] && sudo nix-channel --add "$old" nixos && sudo nix-channel --update
  return 1
}
# всё сразу: драйверы записываются до сборки, чтобы система пересобиралась один раз
do_all() {
  local rc=0 archive
  archive="$(win11-updater find 2>/dev/null | awk -F'\t' '$1 == "new" { print $2; exit }')"
  step "Система, оболочка и драйверы"
  win11-drivers write
  if [ -n "$archive" ]; then win11-update --system "$archive"; else win11-update --system; fi
  if [ $? -ne 0 ]; then rc=1; win11-drivers restore; else sudo rm -f /etc/nixos/win11-shell/drivers-auto.nix.prev; fi
  do_apps || rc=1
  if [ "$(check_firmware | cut -f2)" = update ]; then do_firmware || rc=1; fi
  return $rc
}

# Очередь. Сначала то, что не требует пересборки (программы, прошивки), затем одна общая
# пересборка для оболочки, NixOS и драйверов, последним - переход на новый выпуск.
do_queue() {
  local item rc=0 archive="" release="" optional="" apps=0 firmware=0 drivers=0 nixos=0 shell=0
  local driver_singles=""
  for item in "$@"; do
    case "$item" in
      apps) apps=1 ;; firmware) firmware=1 ;; drivers) drivers=1 ;; nixos) nixos=1 ;;
      driver=*) driver_singles="$driver_singles ${item#driver=}" ;;
      shell) shell=1 ;; shell=*) shell=1; archive="${item#shell=}" ;;
      release=*) release="${item#release=}" ;;
      optional=*|optional-off=*) optional="$optional $item" ;;
      *) echo "Неизвестный пункт очереди: $item"; rc=1 ;;
    esac
  done
  echo "В очереди: $*"
  [ "$apps" -eq 1 ] && { do_apps || rc=1; }
  [ "$firmware" -eq 1 ] && { do_firmware || rc=1; }
  for d in $driver_singles; do
    do_driver_single "$d" || rc=1
  done
  if [ "$shell" -eq 1 ] || [ "$nixos" -eq 1 ]; then
    step "Пересборка: $([ "$shell" -eq 1 ] && printf 'оболочка ')$([ "$nixos" -eq 1 ] && printf 'NixOS ')$([ "$drivers" -eq 1 ] && printf 'драйверы')"
    [ "$drivers" -eq 1 ] && win11-drivers write
    set --
    [ "$nixos" -eq 1 ] && set -- --system
    [ -n "$archive" ] && set -- "$@" "$archive"
    if win11-update "$@"; then
      [ "$drivers" -eq 1 ] && sudo rm -f /etc/nixos/win11-shell/drivers-auto.nix.prev
    else
      rc=1
      if [ "$drivers" -eq 1 ]; then
        win11-drivers restore
        echo "Сборка не прошла. Драйверы возвращены прежние: поставьте их отдельно, кнопкой у строки драйвера -"
        echo "тогда будут перебраны запасные варианты."
      fi
    fi
  elif [ "$drivers" -eq 1 ]; then
    do_drivers || rc=1
  fi
  [ -n "$release" ] && { do_release "$release" || rc=1; }
  for item in $optional; do
    step "Необязательное: ${item#*=}"
    case "$item" in
      optional-off=*) win11-drivers optional "${item#*=}" off || rc=1 ;;
      *) win11-drivers optional "${item#*=}" on || rc=1 ;;
    esac
  done
  return $rc
}

run_in_window() {
  exec 9> "$STATE/updater.lock"
  flock -n 9 || { notify-send -a win11-shell "Центр обновления Windows" "Обновление уже идёт"; exit 0; }
  kitty --title "Центр обновления Windows - ход работы" "$0" _run "$@"
  # оболочка запускает следующее из очереди; старая версия оболочки этой команды не знает
  qs -p /etc/win11-shell ipc call shell updatesDone >/dev/null 2>&1 \
    || qs -p /etc/win11-shell ipc call shell updatesCheck >/dev/null 2>&1
}

case "${1:-}" in
  check) check_shell; check_nixos; check_apps; check_drivers; check_optional; check_firmware ;;
  apply) shift; [ -n "${1:-}" ] || { echo "Что установить? shell, nixos, release, apps, drivers, driver, firmware, all" >&2; exit 1; }
         run_in_window "$@" ;;
  _run)
    show_logo
    what="${2:-}"; shift 2
    old_k="$(readlink -f /run/booted-system/kernel 2>/dev/null || true)"
    case "$what" in
      shell) do_shell "$@" ;; nixos) do_nixos ;; release) do_release "${1:-}" ;;
      apps) do_apps ;; drivers) do_drivers ;; driver) do_driver_single "${1:-}" ;;
      firmware) do_firmware ;; all) do_all ;; queue) do_queue "$@" ;;
      *) echo "Неизвестный раздел: $what"; false ;;
    esac
    code=$?; echo
    case "$what" in
      shell|nixos|all) ;;
      *)
        if [ "$code" -eq 0 ]; then
          echo -e "\033[1;32mОБНОВЛЕНИЕ ПРИМЕНЕНО НА ЛЕТУ\033[0m"
          echo "    Перезагрузка не требуется."
        else
          echo -e "\033[1;31mНе всё удалось (код $code). Система осталась рабочей. Текст выше пришлите разработчику.\033[0m"
        fi
        ;;
    esac
    echo; printf 'Нажмите Enter, чтобы закрыть окно. '; read -r _ ;;
  *) sed -n '1,6p' "$0" | sed 's/^# \{0,1\}//' ;;
esac
