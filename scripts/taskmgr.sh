# win11-taskmgr - данные для диспетчера задач оболочки.
#   win11-taskmgr watch [СЕКУНДЫ]   поток кадров: строки perf/proc, в конце кадра строка end
#   win11-taskmgr frame             один кадр
#   win11-taskmgr services          службы systemd: svc<TAB>имя<TAB>pid<TAB>описание<TAB>состояние<TAB>подсостояние
#   win11-taskmgr startup           автозагрузка: auto<TAB>файл<TAB>название<TAB>1|0<TAB>user|system<TAB>команда
#   win11-taskmgr startup-toggle ФАЙЛ   включить или выключить запись автозагрузки
#   win11-taskmgr kill PID [force]  завершить процесс (force - немедленно)
export PATH="$PATH:/run/current-system/sw/bin"
export LC_ALL=C.UTF-8
TMP="${XDG_RUNTIME_DIR:-/tmp}/win11-taskmgr.$$"
USER_AUTO="${XDG_CONFIG_HOME:-$HOME/.config}/autostart"

info() {
  awk -F': *' '/^model name/ { if (!n++) name = $2 } /^cpu MHz/ { mhz = $2 }
               END { printf "info\tcpu\t%s\t%d\t%d\n", name, n, mhz }' /proc/cpuinfo
}

# Один кадр. Загрузка считается как разница с прошлым кадром, который лежит в $TMP/prev.
frame() {
  ps -eo pid=,user:24=,args= > "$TMP/ps" 2>/dev/null
  cat /proc/[0-9]*/stat > "$TMP/stat" 2>/dev/null
  : > "$TMP/io"
  for f in /proc/[0-9]*/io; do
    [ -r "$f" ] || continue
    pid=${f#/proc/}; pid=${pid%/io}; read_bytes=; write_bytes=
    while read -r key value; do
      case "$key" in read_bytes:) read_bytes=$value ;; write_bytes:) write_bytes=$value ;; esac
    done < "$f" 2>/dev/null || continue
    [ -n "$read_bytes" ] && [ -n "$write_bytes" ] && printf '%s %s %s\n' "$pid" "$read_bytes" "$write_bytes" >> "$TMP/io"
  done
  awk -v prev="$TMP/prev" -v next_="$TMP/next" -v psf="$TMP/ps" -v iof="$TMP/io" -v now="$(date +%s.%N)" \
      -v page="$(getconf PAGESIZE 2>/dev/null || echo 4096)" -v tick="$(getconf CLK_TCK 2>/dev/null || echo 100)" '
    BEGIN {
      OFS = "\t"
      while ((getline l < prev) > 0) { n = split(l, a, " "); old[a[1]] = a[2]; old2[a[1]] = a[3]; old3[a[1]] = a[4] }
      while ((getline l < psf) > 0) {
        sub(/^ +/, "", l); pid = l; sub(/ .*/, "", pid)
        rest = l; sub(/^[0-9]+ +/, "", rest); u = rest; sub(/ .*/, "", u); sub(/^[^ ]+ */, "", rest)
        gsub(/\t/, " ", rest); user[pid] = u; args[pid] = rest
      }
      while ((getline l < iof) > 0) { split(l, a, " "); io_read[a[1]] = a[2]; io_write[a[1]] = a[3] }
      dt = ("t" in old) ? now - old["t"] : 0
      printf "t %s\n", now > next_
    }
    FILENAME == "/proc/stat" {
      if ($1 == "cpu") {
        total = 0; for (i = 2; i <= 9; i++) total += $i
        idle = $5 + $6
        dtotal = ("cpu" in old) ? total - old["cpu"] : 0
        didle = ("cpu" in old) ? idle - old2["cpu"] : 0
        printf "cpu %s %s\n", total, idle > next_
        cpu = dtotal > 0 ? 100 * (1 - didle / dtotal) : 0
      }
      if ($1 == "procs_running") running = $2
      next
    }
    FILENAME == "/proc/uptime" { uptime = int($1); next }
    FILENAME == "/proc/meminfo" { m[$1] = $2; next }
    FILENAME == "/proc/diskstats" {
      if ($3 !~ /^(sd[a-z]+|vd[a-z]+|nvme[0-9]+n[0-9]+|mmcblk[0-9]+)$/) next
      k = "d:" $3
      if (k in old && dt > 0) print "perf", "disk", $3, int(($6 - old[k]) * 512 / dt), int(($10 - old2[k]) * 512 / dt), int(($13 - old3[k]) / (dt * 10))
      else print "perf", "disk", $3, 0, 0, 0
      printf "%s %s %s %s\n", k, $6, $10, $13 > next_
      next
    }
    FILENAME == "/proc/net/dev" {
      if ($0 !~ /:/) next
      l = $0; sub(/^ +/, "", l); name = l; sub(/:.*/, "", name); sub(/^[^:]*: */, "", l); split(l, f, " +")
      if (name == "lo") next
      k = "n:" name
      if (k in old && dt > 0) print "perf", "net", name, int((f[1] - old[k]) / dt), int((f[9] - old2[k]) / dt)
      else print "perf", "net", name, 0, 0
      printf "%s %s %s\n", k, f[1], f[9] > next_
      next
    }
    {
      # /proc/PID/stat: имя в скобках может содержать пробелы и скобки - ищем последнюю ")"
      pid = $1; i = index($0, "("); p = 0; r = $0
      while ((k = index(substr(r, p + 1), ")")) > 0) p += k
      comm = substr(r, i + 1, p - i - 1)
      split(substr(r, p + 2), f, " ")
      if (f[2] == 2 || pid == 2) next                 # потоки ядра
      ticks = f[12] + f[13]
      d = (pid in old) ? ticks - old[pid] : 0
      printf "%s %s\n", pid, ticks > next_
      disk = -1; ik = "io:" pid
      if (pid in io_read) {
        if ((ik in old) && old3[ik] == f[20] && dt > 0) disk = int((io_read[pid] - old[ik] + io_write[pid] - old2[ik]) / dt)
        printf "%s %s %s %s\n", ik, io_read[pid], io_write[pid], f[20] > next_
      }
      procs++; threads += f[18]
      print "proc", pid, f[2], (pid in user ? user[pid] : "?"), (dtotal > 0 ? sprintf("%.1f", 100 * d / dtotal) : "0.0"), \
            int(f[22] * page / 1024), f[18], f[1], int(ticks / tick), comm, (pid in args ? args[pid] : comm), disk
    }
    END {
      print "perf", "cpu", sprintf("%.1f", cpu), uptime, procs, threads
      print "perf", "mem", m["MemTotal:"] - m["MemAvailable:"], m["MemTotal:"], m["MemAvailable:"], m["Cached:"], \
            m["SwapTotal:"] - m["SwapFree:"], m["SwapTotal:"]
    }
  ' /proc/stat /proc/uptime /proc/meminfo /proc/diskstats /proc/net/dev "$TMP/stat"
  mv -f "$TMP/next" "$TMP/prev" 2>/dev/null
  if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi --query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits 2>/dev/null \
      | awk -F', *' '{ printf "perf\tgpu\t%s\t%d\t%d\t%d\t%d\n", $1, $2, $3, $4, $5 }'
  else
    for g in /sys/class/drm/card[0-9]/device/gpu_busy_percent; do
      [ -r "$g" ] && printf 'perf\tgpu\t%s\t%d\t0\t0\t0\n' "$(basename "$(dirname "$(dirname "$g")")")" "$(cat "$g")"
    done
  fi
  echo end
}

desktop_key() { sed -n "s/^$2=//p" "$1" | head -n 1; }
startup() {
  local f base name hidden seen=" "
  for f in "$USER_AUTO"/*.desktop /etc/xdg/autostart/*.desktop; do
    [ -r "$f" ] || continue
    base="${f##*/}"
    case "$seen" in *" $base "*) continue ;; esac     # запись пользователя перекрывает системную
    seen="$seen$base "
    name="$(desktop_key "$f" Name)"; hidden="$(desktop_key "$f" Hidden)"
    printf 'auto\t%s\t%s\t%s\t%s\t%s\n' "$base" "${name:-${base%.desktop}}" "$([ "$hidden" = true ] && echo 0 || echo 1)" \
      "$([ -e "/etc/xdg/autostart/$base" ] && echo system || echo user)" "$(desktop_key "$f" Exec)"
  done
}
startup_toggle() {
  local base="${1##*/}" mine="$USER_AUTO/${1##*/}" sys="/etc/xdg/autostart/${1##*/}"
  case "$base" in *.desktop) ;; *) echo "нужен файл .desktop" >&2; return 1 ;; esac
  mkdir -p "$USER_AUTO"
  if [ ! -e "$mine" ]; then
    [ -r "$sys" ] || { echo "нет такой записи" >&2; return 1; }
    cp "$sys" "$mine" && chmod u+w "$mine"         # системную запись выключает копия с Hidden=true
  fi
  if [ "$(desktop_key "$mine" Hidden)" = true ]; then
    if [ -e "$sys" ]; then rm -f "$mine"; else sed -i '/^Hidden=/d' "$mine"; fi
  else
    sed -i '/^Hidden=/d' "$mine"; echo "Hidden=true" >> "$mine"
  fi
}

# Only the selected user's application process; never acquire elevated privileges.
efficiency() {
  local pid="${1:-}" action="${2:-}" uid comm stat rest start saved class level dir file
  case "$pid" in ''|*[!0-9]*) echo 'Invalid PID' >&2; return 1 ;; esac
  case "$action" in on|off|toggle) ;; *) echo 'Use on, off or toggle' >&2; return 1 ;; esac
  command -v ionice >/dev/null || { echo 'ionice is unavailable' >&2; return 1; }
  [ "$pid" -gt 1 ] && [ "$pid" != "$$" ] || return 1
  uid=$(awk '/^Uid:/ {print $2; exit}' "/proc/$pid/status" 2>/dev/null) || return 1
  [ "$uid" = "$(id -u)" ] || { echo 'Only your own processes are allowed' >&2; return 1; }
  comm=$(cat "/proc/$pid/comm" 2>/dev/null) || return 1
  case "$comm" in systemd*|niri|qs|quickshell|dbus*|polkit*|pipewire*|wireplumber|Xwayland|xwayland*) echo 'Protected system or desktop process' >&2; return 1 ;; esac
  stat=$(cat "/proc/$pid/stat" 2>/dev/null) || return 1
  rest=${stat##*) }; set -- $rest
  [ "$#" -ge 20 ] || return 1
  start=${20}
  dir="${XDG_RUNTIME_DIR:-/tmp}/win11-taskmgr-efficiency-$(id -u)"
  (umask 077; mkdir -p "$dir") || return 1
  file="$dir/$pid-$start"
  if [ "$action" = toggle ]; then
    if [ -f "$file" ]; then action=off; else action=on; fi
  fi
  if [ "$action" = on ]; then
    [ ! -e "$file" ] || { echo 'Efficiency mode is already active.'; return 0; }
    saved=$(LC_ALL=C ionice -p "$pid") || return 1
    case "$saved" in
      'none: prio '*) class=0; level=0 ;;
      'best-effort: prio '*) class=2; level=${saved##* } ;;
      'idle'*) class=3; level=0 ;;
      *) echo 'Unsupported I/O priority; unchanged.' >&2; return 1 ;;
    esac
    printf '%s %s\n' "$class" "$level" > "$file" || return 1
    if ! ionice -c 3 -p "$pid"; then rm -f "$file"; return 1; fi
    echo 'Efficiency mode enabled: idle I/O priority for this process only.'
  else
    [ -f "$file" ] || { echo 'No saved original priority for this process.'; return 1; }
    read -r class level < "$file"
    case "$class:$level" in 0:0|3:0|2:[0-7]) ;; *) echo 'Invalid saved priority.' >&2; return 1 ;; esac
    if [ "$class" = 2 ]; then ionice -c "$class" -n "$level" -p "$pid"; else ionice -c "$class" -p "$pid"; fi || return 1
    rm -f "$file"
    echo 'Original I/O priority restored.'
  fi
}

case "${1:-}" in
  watch|frame)
    mkdir -p "$TMP" || exit 1
    trap 'rm -rf "$TMP"' EXIT
    trap 'exit 0' INT TERM HUP
    info
    if [ "$1" = frame ]; then frame >/dev/null; sleep 1; frame; exit 0; fi
    while frame; do sleep "${2:-2}"; done ;;
  users-memory)
    ps -eo pid=,user:24= 2>/dev/null | while read -r pid user; do
      [ -n "$pid" ] || continue
      value=$(awk '/^Pss:/ {print $2; found=1; exit} END {if (!found) exit 1}' "/proc/$pid/smaps_rollup" 2>/dev/null) || value=""
      printf '%s\t%s\n' "$user" "$value"
    done | awk -F '\t' '{ total[$1]++; if ($2 != "") { memory[$1]+=$2; visible[$1]++ } }
      END { for (u in total) printf "userpss\t%s\t%.0f\t%d\t%d\n", u,memory[u],visible[u],total[u] }' ;;
  services)
    systemctl show --type=service --all --no-pager -p Id -p MainPID -p Description -p ActiveState -p SubState 2>/dev/null \
      | awk -F= 'function flush() { if (v["Id"] != "") printf "svc\t%s\t%s\t%s\t%s\t%s\n", v["Id"], v["MainPID"], v["Description"], v["ActiveState"], v["SubState"]; delete v }
                 /^$/ { flush(); next } { k = $1; sub(/^[^=]*=/, ""); v[k] = $0 } END { flush() }' | sort -t "$(printf '\t')" -k2,2 ;;
  startup) startup ;;
  startup-toggle) startup_toggle "${2:-}" ;;
  efficiency) efficiency "${2:-}" "${3:-}" ;;
  kill)
    case "${2:-}" in ""|*[!0-9]*) echo "нужен номер процесса" >&2; exit 1 ;; esac
    if [ "${3:-}" = force ]; then kill -KILL "$2"; else kill -TERM "$2"; fi ;;
  *) sed -n '1,7p' "$0" | sed 's/^# \{0,1\}//' ;;
esac
