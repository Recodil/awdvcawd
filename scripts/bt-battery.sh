#!/usr/bin/env bash
# Опрос всех подключённых периферийных устройств (Bluetooth и USB: мыши, клавиатуры,
# наушники, геймпады) и уровня их заряда (если поддерживается).
# Работает на реальном железе, ноутбуках и в виртуальных машинах (VMware, VirtualBox, KVM).
# Выводит JSON-массив: [{"id":"...","type":"headphones|mouse|keyboard|gamepad","name":"...","percent":93,"status":"connected"}]
set -u

devices=()
seen=""

add_device() {
  local id="$1" type="$2" name="$3" pct="${4:--1}" status="${5:-connected}"
  [ -n "$name" ] || return 0
  # защита от дубликатов по имени или ID
  local key; key="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')"
  case " $seen " in
    *" $key "*) return 0 ;;
  esac
  seen="$seen $key"

  # валидация процента (-1 = нет батареи / проводное устройство)
  if ! { [ -n "$pct" ] && [ "$pct" -ge 0 ] 2>/dev/null && [ "$pct" -le 100 ] 2>/dev/null; }; then
    pct=-1
  fi

  local esc_name
  esc_name="$(printf '%s' "$name" | sed 's/["\\]/\\&/g')"
  devices+=("{\"id\":\"$id\",\"type\":\"$type\",\"name\":\"$esc_name\",\"percent\":$pct,\"status\":\"$status\"}")
}

detect_type() {
  local str
  str="$(printf '%s %s' "${1:-}" "${2:-}" | tr '[:upper:]' '[:lower:]')"
  case "$str" in
    *mouse*|*мышь*|*trackball*|*touchpad*|*тачпад*) echo "mouse" ;;
    *keyboard*|*клавиатура*|*клава*|*kbd*) echo "keyboard" ;;
    *gamepad*|*controller*|*джойстик*|*xbox*|*dualsense*|*joystick*) echo "gamepad" ;;
    *audio*|*headset*|*headphone*|*наушник*|*гарнитур*|*airpods*) echo "headphones" ;;
    *) echo "headphones" ;;
  esac
}

# 1. Проверяем Bluetooth и HID батареи через UPower
if command -v upower >/dev/null 2>&1; then
  while IFS= read -r dev; do
    [ -n "$dev" ] || continue
    info="$(upower -i "$dev" 2>/dev/null || true)"
    pct="$(printf '%s\n' "$info" | awk '/percentage:/ {gsub(/%/,""); print int($2)}' | head -n1)"
    [ -n "$pct" ] || continue
    name="$(printf '%s\n' "$info" | awk -F: '/model:/ {sub(/^[ \t]+/,""); print $2}' | head -n1)"
    [ -n "$name" ] || name="$(basename "$dev")"
    dtype="$(detect_type "$dev" "$name")"
    add_device "$(basename "$dev")" "$dtype" "$name" "$pct" "connected"
  done < <(upower -e 2>/dev/null | grep -E '(headset|headphone|mouse|keyboard|gaming|input)' || true)
fi

# 2. Проверяем /sys/class/power_supply/hid* (Bluetooth LE / HID)
for p in /sys/class/power_supply/hid* /sys/class/power_supply/*bluetooth*; do
  [ -d "$p" ] || continue
  [ -f "$p/capacity" ] || continue
  pct="$(cat "$p/capacity" 2>/dev/null || true)"
  [ -n "$pct" ] || continue
  name="$(cat "$p/model_name" 2>/dev/null || basename "$p")"
  dtype="$(detect_type "$p" "$name")"
  add_device "$(basename "$p")" "$dtype" "$name" "$pct" "connected"
done

# 3. Проверяем bluetoothctl
if command -v bluetoothctl >/dev/null 2>&1; then
  while IFS= read -r line; do
    mac="$(printf '%s\n' "$line" | awk '{print $2}')"
    [ -n "$mac" ] || continue
    binfo="$(bluetoothctl info "$mac" 2>/dev/null || true)"
    pct="$(printf '%s\n' "$binfo" | awk '/Battery Percentage:/ {
      for (i=1; i<=NF; i++) {
        if ($i ~ /^\([0-9]+\)$/) { gsub(/[()]/,"",$i); print $i; exit }
        if ($i ~ /^[0-9]+$/ && $(i-1) ~ /Percentage/) { print $i; exit }
      }
    }')"
    [ -n "$pct" ] || pct=-1
    name="$(printf '%s\n' "$binfo" | awk -F: '/Name:/ {sub(/^[ \t]+/,""); print $2}' | head -n1)"
    [ -n "$name" ] || name="$mac"
    icon="$(printf '%s\n' "$binfo" | awk -F: '/Icon:/ {sub(/^[ \t]+/,""); print $2}' | head -n1)"
    dtype="$(detect_type "$icon" "$name")"
    add_device "$mac" "$dtype" "$name" "$pct" "connected"
  done < <(bluetoothctl devices Connected 2>/dev/null || true)
fi

# 4. Проверяем все устройства ввода (USB, PS/2, VMware, VirtualBox) из /proc/bus/input/devices
if [ -f /proc/bus/input/devices ]; then
  cur_name=""
  cur_handlers=""
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      N:\ Name=*)
        cur_name="${line#N: Name=}"
        cur_name="${cur_name%\"}"
        cur_name="${cur_name#\"}"
        ;;
      H:\ Handlers=*)
        cur_handlers="${line#H: Handlers=}"
        ;;
      "")
        if [ -n "$cur_name" ]; then
          low="$(printf '%s' "$cur_name" | tr '[:upper:]' '[:lower:]')"
          case "$low" in
            *power\ button*|*sleep\ button*|*video\ bus*|*pcspkr*|*hda\ intel*|*hdmi*) ;;
            *)
              dtype="keyboard"
              case "$low" in
                *mouse*|*touchpad*|*trackball*) dtype="mouse" ;;
                *gamepad*|*joystick*|*controller*) dtype="gamepad" ;;
                *)
                  case "$cur_handlers" in
                    *mouse*) dtype="mouse" ;;
                    *js*) dtype="gamepad" ;;
                  esac
                  ;;
              esac
              add_device "$cur_name" "$dtype" "$cur_name" -1 "connected"
              ;;
          esac
        fi
        cur_name=""
        cur_handlers=""
        ;;
    esac
  done < /proc/bus/input/devices
fi

# 5. Вывод JSON
if [ "${#devices[@]}" -eq 0 ]; then
  echo "[]"
else
  (IFS=","; echo "[${devices[*]}]")
fi
