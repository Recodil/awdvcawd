# win11-sound - универсальное управление, проверка и починка звука.
# Поддерживает реальное железо (Realtek, Intel SOF, AMD HD Audio, NVIDIA HDMI),
# внешние USB ЦАП / гарнитуры, Bluetooth и виртуальные машины (VMware ES1371, VirtualBox AC97/Intel, KVM).
#
#   win11-sound                 диагностический отчёт
#   win11-sound state           состояние для "Параметров" (выходы, входы, громкость)
#   win11-sound fix             починить звук: снять заглушение ALSA, перезапустить звуковой сервер
#   win11-sound test [ВЫХОД]    проиграть проверочный звук
#   win11-sound out [НОМЕР/ИМЯ] выбрать устройство вывода
#   win11-sound in [НОМЕР/ИМЯ]  выбрать устройство ввода (микрофон)
#   win11-sound vol [0-100]     установить громкость
#   win11-sound mute [on|off]   заглушить / включить звук
export PATH="$PATH:/run/current-system/sw/bin"
export LC_ALL=C

have() { command -v "$1" >/dev/null 2>&1; }
sec() { echo; echo "== $1 =="; }

KIT=/etc/nixos/win11-shell
cards() { sed -n 's/^ *\([0-9]\+\) \[.*/\1/p' /proc/asound/cards 2>/dev/null; }
sinks() { pactl list short sinks 2>/dev/null; }
sources() { pactl list short sources 2>/dev/null | grep -v '\.monitor'; }

is_vm() {
  grep -qiE 'vmware|virtualbox|qemu|kvm|bochs' /sys/class/dmi/id/sys_vendor 2>/dev/null \
    || grep -qiE 'vmware|virtualbox|qemu|kvm' /sys/class/dmi/id/product_name 2>/dev/null
}

report() {
  sec "среда выполнения"
  if is_vm; then
    echo "Виртуальная машина ($(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || echo "VM"))"
    echo "Звук виртуализируется через аудиодрайвер гипервизора хоста."
  else
    echo "Физический компьютер: $(cat /sys/class/dmi/id/product_name 2>/dev/null || echo "ПК")"
  fi

  sec "звуковые карты (ядро Linux / ALSA)"
  if [ -n "$(cards)" ]; then cat /proc/asound/cards; else echo "ядро не видит ни одной звуковой карты"; fi

  sec "микросхемы и кодеки"
  cat /proc/asound/card*/codec#* 2>/dev/null | grep -E '^(Codec|Vendor Id|Subsystem Id):' || echo "нет сведений (виртуальная или USB-карта)"

  sec "устройства на шинах"
  if have lspci; then lspci -nnk | grep -iA3 'audio' | cut -c1-160; fi
  lsusb 2>/dev/null | grep -iE 'audio|realtek|sound|headset|dac' | cut -c1-120

  sec "звуковой сервер (PipeWire / WirePlumber)"
  for u in pipewire pipewire-pulse wireplumber; do
    printf '%-18s %s\n' "$u" "$(systemctl --user is-active "$u" 2>&1)"
  done

  sec "устройства вывода (воспроизведение)"
  pactl list sinks 2>/dev/null | grep -E '^\s*(Name|Description|State|Mute|Volume):' | head -n 30

  sec "устройства ввода (запись / микрофоны)"
  pactl list sources 2>/dev/null | grep -v '\.monitor' | grep -E '^\s*(Name|Description|State|Mute|Volume):' | head -n 30

  sec "выход по умолчанию"
  pactl get-default-sink 2>&1
  if have wpctl; then wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>&1; fi

  sec "сообщения ядра о звуке"
  journalctl -b -k --no-pager 2>/dev/null | grep -iE 'snd|sof-|hda|alc[0-9]|audio|es1371' | tail -n 20 | cut -c1-200
}

# Микшер ALSA: снимаем заглушение со всех доступных каналов
unmute_alsa() {
  have amixer || return 0
  local c ctl
  for c in $(cards); do
    for ctl in Master Headphone Speaker Front PCM "Line Out" Surround Center LFE "Master Playback" "PCM Playback"; do
      amixer -q -c "$c" sset "$ctl" 85% unmute 2>/dev/null
    done
    amixer -q -c "$c" sset "Auto-Mute Mode" Disabled 2>/dev/null
    amixer -q -c "$c" sset "IEC958" on 2>/dev/null
  done
}

# Выбор активного профиля для всех обнаруженных карт
pick_profiles() {
  local card prof
  pactl list short cards 2>/dev/null | awk '{ print $2 }' | while read -r card; do
    # проверяем доступные профили
    for prof in output:analog-stereo+input:analog-stereo output:analog-stereo \
                pro-audio output:stereo-fallback "output:analog-surround-51"; do
      pactl set-card-profile "$card" "$prof" 2>/dev/null && break
    done
  done
}

pick_default() {
  local name
  # 1. Приоритет: аналоговый выход / виртуальный VMware / USB
  name="$(sinks | awk '{ print $2 }' | grep -iE 'analog|es1371|vmware|usb|headset' | head -n 1)"
  # 2. Если нет - любой не-HDMI
  [ -n "$name" ] || name="$(sinks | awk '{ print $2 }' | grep -viE 'hdmi|nv' | head -n 1)"
  # 3. Если только HDMI
  [ -n "$name" ] || name="$(sinks | awk '{ print $2 }' | head -n 1)"

  [ -n "$name" ] || { echo "  звуковых выходов не обнаружено"; return 1; }
  pactl set-default-sink "$name" && echo "  выход по умолчанию: $name"
  pactl set-sink-mute "$name" 0
  pactl set-sink-volume "$name" 75%
}

TONE="${XDG_RUNTIME_DIR:-/tmp}/win11-tone.wav"
tone() {
  [ -s "$TONE" ] && return 0
  {
    printf 'RIFF\244\076\000\000WAVEfmt \020\000\000\000\001\000\001\000'
    printf '\100\037\000\000\100\037\000\000\001\000\010\000data\200\076\000\000'
    awk 'BEGIN { for (i = 0; i < 16000; i++) printf "%c", (int(i * 880 / 8000) % 2 ? 176 : 80) }'
  } > "$TONE"
}

beep() {
  tone
  local dev="${1:-$(pactl get-default-sink 2>/dev/null)}"
  if [ -n "$dev" ] && have paplay; then
    timeout 5 paplay --device="$dev" "$TONE" 2>/dev/null && return 0
  fi
  if have pw-play; then
    timeout 5 pw-play ${dev:+--target "$dev"} "$TONE" 2>/dev/null && return 0
  fi
  if have aplay; then
    timeout 5 aplay -q "$TONE" 2>/dev/null && return 0
  fi
  echo "Не удалось проиграть тестовый звук." >&2
  return 1
}

fix() {
  echo "== Починка звука =="
  echo "1. Снимаю заглушение в ALSA (все каналы)..."
  unmute_alsa
  echo "2. Настраиваю профили устройств..."
  pick_profiles
  echo "3. Перезапускаю службы звука PipeWire..."
  systemctl --user restart wireplumber pipewire pipewire-pulse 2>/dev/null || true
  sleep 1.2
  echo "4. Выбираю рабочий аудиовыход..."
  pick_default
  echo "5. Проигрываю проверочный звук..."
  if beep; then
    echo "Готово! Звук должен работать."
  else
    echo "Проверочный звук не прозвучал. Запустите 'win11-sound' для подробного отчёта."
  fi
}

state() {
  local def_sink def_source has_j=0
  def_sink="$(pactl get-default-sink 2>/dev/null)"
  def_source="$(pactl get-default-source 2>/dev/null)"

  # Определяем, поддерживает ли материнская плата аппаратный Realtek HDA
  if [ -f /proc/asound/cards ] && grep -qiE 'alc[0-9]|realtek' /proc/asound/card*/codec#* 2>/dev/null && ! is_vm; then
    has_j=1
  fi

  printf 'has_jacks\t%s\n' "$has_j"
  printf 'is_vm\t%s\n' "$([ "$(is_vm; echo $?)" -eq 0 ] && echo 1 || echo 0)"
  printf 'default\t%s\n' "$def_sink"
  printf 'default_source\t%s\n' "$def_source"

  # Выходы (воспроизведение)
  pactl list sinks 2>/dev/null | awk -F': ' '
    /^\tName: / { name = $2 }
    /^\tDescription: / { n++; printf "sink\t%d\t%s\t%s\n", n, name, $2 }'

  # Входы (микрофоны / запись)
  pactl list sources 2>/dev/null | awk -F': ' '
    /^\tName: / { name = $2; if (name ~ /\.monitor$/) next }
    /^\tDescription: / { m++; printf "source\t%d\t%s\t%s\n", m, name, $2 }'
}

case "${1:-}" in
  "") report ;;
  state) state ;;
  fix) fix ;;
  test) beep "${2:-}" ;;
  vol)
    pct="${2:-70}"
    pactl set-sink-volume @DEFAULT_AUDIO_SINK@ "${pct}%" 2>/dev/null \
      || (have wpctl && wpctl set-volume @DEFAULT_AUDIO_SINK@ "$(awk "BEGIN {print $pct/100}")")
    ;;
  mute)
    val="${2:-toggle}"
    pactl set-sink-mute @DEFAULT_AUDIO_SINK@ "$val" 2>/dev/null \
      || (have wpctl && wpctl set-mute @DEFAULT_AUDIO_SINK@ "$val")
    ;;
  out)
    if [ -n "${2:-}" ]; then
      target="$2"
      if printf '%s' "$target" | grep -qE '^[0-9]+$'; then
        target="$(sinks | awk -v n="$target" 'NR == n { print $2 }')"
      fi
      [ -n "$target" ] || { echo "Устройство вывода не найдено"; exit 1; }
      pactl set-default-sink "$target" && pactl set-sink-mute "$target" 0 && echo "Выбран выход: $target"
    else
      sinks | awk '{ printf "%d  %s\n", NR, $2 }'
    fi
    ;;
  in)
    if [ -n "${2:-}" ]; then
      target="$2"
      if printf '%s' "$target" | grep -qE '^[0-9]+$'; then
        target="$(sources | awk -v n="$target" 'NR == n { print $2 }')"
      fi
      [ -n "$target" ] || { echo "Устройство ввода не найдено"; exit 1; }
      pactl set-default-source "$target" && echo "Выбран вход: $target"
    else
      sources | awk '{ printf "%d  %s\n", NR, $2 }'
    fi
    ;;

  *) sed -n '1,12p' "$0" | sed 's/^# \{0,1\}//' ;;
esac
