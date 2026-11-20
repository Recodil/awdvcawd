# win11-drivers - подбор и установка драйверов под оборудование этого компьютера.
#   win11-drivers detect    что найдено: id<TAB>раздел<TAB>устройство<TAB>драйвер<TAB>состояние<TAB>пояснение<TAB>источник
#   win11-drivers search    подробный отчёт по оборудованию и найденным драйверам
#   win11-drivers install ИМЯ установить конкретный драйвер из источников NixOS
#   win11-drivers plan      показать файл drivers-auto.nix, который будет записан
#   win11-drivers status    pending - есть что установить, ok - всё уже стоит
#   win11-drivers apply     записать файл и пересобрать систему (при неудаче вернуть прежний)
#   win11-drivers nvidia [ВАРИАНТ]   как ставить драйвер NVIDIA: stable, beta, lts, lts-closed
#   win11-drivers optional  необязательное (свежее ядро, новый драйвер NVIDIA, все прошивки):
#                           имя<TAB>состояние<TAB>название<TAB>пояснение;  optional ИМЯ on|off - включить или убрать
#   win11-drivers write     только записать файл;  restore - вернуть прежний;  reset - убрать подобранное
# Состояния: ok - работает штатный драйвер, install - будет установлен, applied - уже установлен,
#            update - доступно обновление, offer - рекомендуется, none - драйвер не найден.
export PATH="$PATH:/run/current-system/sw/bin"
export LC_ALL=C.UTF-8
TARGET="${WIN11_DRIVERS_FILE:-/etc/nixos/win11-shell/drivers-auto.nix}"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/win11-shell"
BUILD_LOG="$STATE/drivers-build.log"

# Драйвер NVIDIA собирается под конкретное ядро. Под самое новое ядро он собирается не всегда,
# поэтому вариантов несколько, от близкого к системе до самого надёжного:
#   stable      драйвер из выпуска, ядро не трогаем
#   beta        более новый драйвер: в нём поддержка свежих ядер появляется раньше
#   lts         ядро с долгой поддержкой (под него драйвер собирается всегда) и обычный драйвер
#   lts-closed  то же, но закрытый модуль ядра вместо открытого
NVIDIA_VARIANTS="stable lts lts-closed beta"
# сами перебираются только эти; beta обычно той же версии, что stable, и ставится лишь по просьбе
NVIDIA_AUTO="stable lts lts-closed"
NVIDIA_VARIANT="${WIN11_NVIDIA:-}"
if [ -z "$NVIDIA_VARIANT" ]; then
  NVIDIA_VARIANT="$(sed -n 's/^  # nvidia-variant: //p' "$TARGET" 2>/dev/null | head -n 1)"
fi
[ -n "$NVIDIA_VARIANT" ] || NVIDIA_VARIANT=stable
T="$(printf '\t')"
SYS="${WIN11_SYS:-/sys}"      # другой корень нужен только для проверки сценария

# Необязательное включается только по просьбе и запоминается в самом файле (# optional: имя).
declare -A OPT=()
while read -r o; do [ -n "$o" ] && OPT["$o"]=1; done < <(sed -n 's/^  # optional: //p' "$TARGET" 2>/dev/null)
opt() { [ -n "${OPT[$1]:-}" ]; }

declare -A FEATURE=()      # что нужно включить: имя -> параметр (например, адреса шин для PRIME)
ROWS=""

# id, class, name, driver, state, note, source
row() { ROWS+="$1$T$2$T$3$T$4$T$5$T$6$T$7"$'\n'; }
need() { FEATURE["$1"]="${2:-1}"; }
applied() { [ -r "$TARGET" ] && grep -q "^  # feature: $1\$" "$TARGET"; }
# состояние строки для драйвера, который ставит этот сценарий
state_of() { if applied "$1"; then echo applied; else echo install; fi; }

pci_name() {
  local n=""
  if command -v lspci >/dev/null 2>&1; then
    n="$(lspci -s "$1" 2>/dev/null | cut -d' ' -f2- | sed 's/^[^:]*: //')"
  fi
  printf '%s' "${n:-устройство $2:$3}"
}
# шина для hardware.nvidia.prime: 0000:01:00.0 -> PCI:1:0:0
bus_id() {
  local s="${1#*:}"
  printf 'PCI:%d:%d:%d' "0x${s%%:*}" "0x$(printf '%s' "$s" | cut -d: -f2 | cut -d. -f1)" "0x${s##*.}"
}

gpu_nvidia() {   # slot device driver name
  local id=$((16#$2)) feat
  if [ "$id" -ge $((16#1e00)) ]; then feat=nvidia-open
  elif [ "$id" -ge $((16#1340)) ]; then feat=nvidia-closed
  else
    row "nouveau" "Видеокарта" "$4" "${3:-nouveau}" ok "старая модель: фирменный драйвер её уже не поддерживает, работает свободный nouveau" "NixOS Mesa / nouveau"
    return
  fi
  need "$feat"; NVIDIA_BUS="$(bus_id "$1")"
  row "$feat" "Видеокарта" "$4" "${3:-нет}" "$(state_of "$feat")" "фирменный драйвер NVIDIA" "NixOS Hardware (nixpkgs)"
}

scan_pci() {
  local d slot class vendor device driver name
  [ -d "$SYS/bus/pci/devices" ] || return 0
  for d in "$SYS"/bus/pci/devices/*; do
    [ -r "$d/class" ] || continue
    slot="${d##*/}"
    class="$(cut -c3-6 "$d/class")"
    vendor="$(cut -c3- "$d/vendor")"; device="$(cut -c3- "$d/device")"
    driver=""; [ -e "$d/driver" ] && driver="$(basename "$(readlink "$d/driver")")"
    case "$class" in
      0300|0302|0380)
        name="$(pci_name "$slot" "$vendor" "$device")"
        case "$vendor" in
          10de) gpu_nvidia "$slot" "$device" "$driver" "$name" ;;
          8086) IGPU_KIND=intel; IGPU_BUS="$(bus_id "$slot")"; need intel-media
                row "intel-media" "Видеокарта" "$name" "${driver:-i915}" "$(state_of intel-media)" "аппаратное ускорение Intel VA-API / QSV" "NixOS Hardware (nixpkgs)" ;;
          1002) IGPU_KIND=amdgpu; IGPU_BUS="$(bus_id "$slot")"
                row "amdgpu" "Видеокарта" "$name" "${driver:-amdgpu}" ok "драйвер входит в систему (Mesa/RADV)" "NixOS Mesa" ;;
          80ee) need vbox;   row "vbox" "Виртуальная машина" "VirtualBox" "${driver:-нет}" "$(state_of vbox)" "дополнения гостевой системы" "NixOS virtualbox.guest" ;;
          15ad) need vmware; row "vmware" "Виртуальная машина" "VMware" "${driver:-нет}" "$(state_of vmware)" "дополнения гостевой системы" "NixOS vmware.guest" ;;
          1af4|1b36|1234) need qemu; row "qemu" "Виртуальная машина" "QEMU / KVM" "${driver:-нет}" "$(state_of qemu)" "гостевой агент и буфер обмена" "NixOS services.qemuGuest" ;;
          *) row "gpu-other" "Видеокарта" "$name" "${driver:-нет}" "$([ -n "$driver" ] && echo ok || echo none)" "$([ -n "$driver" ] && echo "драйвер загружен" || echo "драйвер не загружен")" "Ядро Linux" ;;
        esac ;;
      0401|0403)
        name="$(pci_name "$slot" "$vendor" "$device")"
        if [ "$vendor" = 8086 ] || [ "$vendor" = 1022 ]; then
          if applied sof-firmware; then
            row "sof-firmware" "Звук" "$name" "${driver:-snd_hda_intel}" applied "прошивки Sound Open Firmware (SOF)" "NixOS pkgs.sof-firmware"
          elif [ -z "$driver" ] || dmesg 2>/dev/null | grep -qiE 'sof.*firmware|dsp.*firmware'; then
            need sof-firmware
            row "sof-firmware" "Звук" "$name" "${driver:-нет}" install "требуются прошивки SOF Firmware для DSP" "NixOS pkgs.sof-firmware"
          else
            row "sound-pci" "Звук" "$name" "${driver:-snd_hda_intel}" ok "драйвер звука входит в систему" "Ядро Linux (PipeWire/ALSA)"
          fi
        else
          row "sound-pci" "Звук" "$name" "${driver:-нет}" "$([ -n "$driver" ] && echo ok || echo none)" \
              "$([ -n "$driver" ] && echo "драйвер входит в систему" || echo "драйвер не загружен")" "Ядро Linux (ALSA)"
        fi ;;
      0280)
        name="$(pci_name "$slot" "$vendor" "$device")"
        if [ -z "$driver" ] && [ "$vendor" = 14e4 ]; then
          need broadcom-sta
          row "broadcom-sta" "Wi-Fi" "$name" "нет" "$(state_of broadcom-sta)" "фирменный драйвер Broadcom (wl)" "NixOS pkgs.broadcom_sta"
        elif [ "$vendor" = 10ec ]; then
          row "realtek-wifi" "Wi-Fi" "$name" "${driver:-rtw88}" "$([ -n "$driver" ] && echo ok || echo install)" "драйвер Realtek Wi-Fi (rtw88/rtw89)" "NixOS Kernel / rtw89"
        else
          row "wifi-pci" "Wi-Fi" "$name" "${driver:-нет}" "$([ -n "$driver" ] && echo ok || echo none)" \
              "$([ -n "$driver" ] && echo "драйвер входит в систему" || echo "подходящий драйвер не найден")" "Ядро Linux"
        fi ;;
      0200)
        name="$(pci_name "$slot" "$vendor" "$device")"
        row "net-pci" "Сеть" "$name" "${driver:-нет}" "$([ -n "$driver" ] && echo ok || echo none)" \
            "$([ -n "$driver" ] && echo "драйвер входит в систему" || echo "драйвер не загружен")" "Ядро Linux" ;;
      01*|02*|04*|07*|09*|0c03|0d*)
        # любая другая плата, которой нужен драйвер: молчим, пока он есть
        if [ -z "$driver" ]; then
          row "pci-other" "Устройство" "$(pci_name "$slot" "$vendor" "$device")" "нет" none \
              "в этом ядре драйвера нет: может помочь более новое ядро или полный набор прошивок (раздел \"Необязательные\")" "NixOS"
        fi ;;
    esac
  done
}

# Виртуализация через systemd-detect-virt (если sysfs не дал точного ответа)
scan_virt() {
  local virt; virt="$(systemd-detect-virt 2>/dev/null || true)"
  case "$virt" in
    vmware)
      if ! has vmware; then
        need vmware
        row "vmware" "Виртуальная машина" "VMware Guest" "open-vm-tools" "$(state_of vmware)" "дополнения гостевой системы VMware" "NixOS vmware.guest"
      fi
      ;;
    oracle|virtualbox)
      if ! has vbox; then
        need vbox
        row "vbox" "Виртуальная машина" "Oracle VirtualBox" "vboxguest" "$(state_of vbox)" "дополнения гостевой системы VirtualBox" "NixOS virtualbox.guest"
      fi
      ;;
    kvm|qemu|bochs)
      if ! has qemu; then
        need qemu
        row "qemu" "Виртуальная машина" "QEMU / KVM" "qemu-ga" "$(state_of qemu)" "гостевой агент и буфер обмена" "NixOS services.qemuGuest"
      fi
      ;;
    microsoft)
      if ! has hyperv; then
        need hyperv
        row "hyperv" "Виртуальная машина" "Hyper-V" "hv_vmbus" "$(state_of hyperv)" "демоны интеграции Hyper-V" "NixOS hypervGuest"
      fi
      ;;
  esac
}

# USB: адаптеры Wi-Fi Realtek без драйвера в ядре, сканеры отпечатков, планшеты
scan_usb() {
  local d id vendor product bound feat name
  [ -d "$SYS/bus/usb/devices" ] || return 0
  for d in "$SYS"/bus/usb/devices/*; do
    [ -r "$d/idVendor" ] || continue
    vendor="$(cat "$d/idVendor")"; product="$(cat "$d/idProduct")"; id="$vendor:$product"
    name="$(cat "$d/product" 2>/dev/null)"; name="${name:-устройство USB $id}"
    bound=0; for i in "$d":*/driver; do [ -e "$i" ] && bound=1; done
    feat=""
    case "$id" in
      0bda:b812|0bda:b82c|2357:012d|2357:0138|7392:b822) feat=rtl88x2bu ;;
      0bda:c811|0bda:c820|0bda:c821|2357:011e|7392:c811) feat=rtl8821cu ;;
      0bda:8812|0bda:881a|2357:0101|2357:0103|7392:a822) feat=rtl8812au ;;
      0bda:0811|0bda:a811|0bda:0821|2357:0120|7392:a811) feat=rtl8821au ;;
      0bda:8813|2357:0106|0b05:1853) feat=rtl8814au ;;
    esac
    if [ -n "$feat" ]; then
      if [ "$bound" -eq 1 ] && ! applied "$feat"; then
        row "$feat" "Wi-Fi" "$name" "в ядре" ok "драйвер входит в систему" "Ядро Linux"
      else
        need "$feat"; row "$feat" "Wi-Fi" "$name" "${feat}" "$(state_of "$feat")" "драйвер адаптера Realtek" "NixOS pkgs.linuxPackages.$feat"
      fi
    fi
    case "$vendor" in
      06cb|138a|27c6|04f3)
        if [ "$(cat "$d/bDeviceClass" 2>/dev/null)" = ff ] || [ "$vendor" = 27c6 ] || [ "$vendor" = 138a ]; then
          case "$name" in *[Ff]inger*|*Goodix*|*Validity*|*Prometheus*)
            need fprintd; row "fprintd" "Отпечаток пальца" "$name" "fprintd" "$(state_of fprintd)" "служба сканера отпечатков" "NixOS services.fprintd" ;;
          esac
        fi ;;
      28bd|256c|5543) # XP-Pen, Huion, UC-Logic
        need digimend; row "digimend" "Планшет" "$name" "digimend" "$(state_of digimend)" "драйвер графического планшета" "NixOS pkgs.digimend" ;;
    esac
  done
}

# Принтеры и сканеры: поиск подключённых устройств HP, Brother, Canon
scan_printers() {
  local d vendor product name
  if [ -d "$SYS/bus/usb/devices" ]; then
    for d in "$SYS"/bus/usb/devices/*; do
      [ -r "$d/idVendor" ] || continue
      vendor="$(cat "$d/idVendor" 2>/dev/null)"
      product="$(cat "$d/idProduct" 2>/dev/null)"
      name="$(cat "$d/product" 2>/dev/null || true)"
      case "$vendor" in
        03f0) # HP
          case "$name" in
            *[Ll]aser[Jj]et*|*[Dd]esk[Jj]et*|*[Pp]rinter*|*HP*|*MFP*)
              local st="install"
              if [ -e "/nix/store" ] && ls /nix/store/*hplip-plugin* >/dev/null 2>&1 || applied hp-plugin; then
                st="applied"
              fi
              row "hp-plugin" "Принтеры и сканеры" "${name:-HP Принтер/МФУ}" "HPLIP Plugin" "$st" \
                  "проприетарный плагин печати и сканирования HP" "HP Linux Imaging and Printing (HPLIP)"
              ;;
          esac
          ;;
        04f9) # Brother
          row "brlaser" "Принтеры и сканеры" "${name:-Brother Принтер}" "brlaser" "$(state_of brlaser)" \
              "драйвер лазерных принтеров Brother" "NixOS pkgs.brlaser"
          ;;
        04a9) # Canon
          row "cups-bjnp" "Принтеры и сканеры" "${name:-Canon Принтер}" "cups-bjnp" "$(state_of cups-bjnp)" \
              "драйвер принтеров Canon BJNP" "NixOS pkgs.cups-bjnp"
          ;;
      esac
    done
  fi

}

scan_firmware() {
  if command -v fwupdmgr >/dev/null 2>&1; then
    local out n
    out="$(timeout 15 fwupdmgr get-updates 2>/dev/null || true)"
    n="$(printf '%s\n' "$out" | grep -ciE 'new version|новая версия' || true)"
    if [ "$n" -gt 0 ]; then
      row "fwupd" "Прошивки" "Прошивки оборудования (LVFS)" "fwupd" update \
          "доступно обновлений прошивок: $n (BIOS/UEFI, контроллеры)" "LVFS Linux Vendor Firmware Service"
    fi
  fi
}

scan_other() {
  local d
  for d in "$SYS"/class/bluetooth/hci*; do
    [ -e "$d" ] && { row "bluetooth" "Bluetooth" "адаптер ${d##*/}" "$(basename "$(readlink "$d/device/driver" 2>/dev/null)" 2>/dev/null)" ok "драйвер входит в систему" "Ядро Linux (BlueZ)"; break; }
  done
  local cpu; cpu="$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ //')"
  [ -n "$cpu" ] && row "cpu" "Процессор" "$cpu" "микрокод $(grep -m1 microcode /proc/cpuinfo | awk '{print $3}')" ok "обновляется вместе с системой" "NixOS hardware.cpu"
  if grep -qi 'AuthenticAMD' /proc/cpuinfo 2>/dev/null; then
    row "zenpower" "Датчики" "AMD Ryzen / Zen" "zenpower" "$(state_of zenpower)" "драйвер датчиков температуры и напряжений" "NixOS pkgs.zenpower"
  fi
}

detect() {
  IGPU_KIND=""; IGPU_BUS=""; NVIDIA_BUS=""
  scan_pci; scan_virt; scan_usb; scan_printers; scan_firmware; scan_other
  # Ноутбук с двумя видеокартами: NVIDIA включается по требованию (nvidia-offload программа).
  # На настольном компьютере монитор подключён к самой NVIDIA, там это не нужно.
  if [ -n "$NVIDIA_BUS" ] && [ -n "$IGPU_BUS" ] && ls "$SYS"/class/power_supply/BAT* >/dev/null 2>&1; then
    need nvidia-prime "$IGPU_KIND $IGPU_BUS $NVIDIA_BUS"
  fi
}

# ---- необязательное: то, что новее штатного ----
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/win11-shell"
# версия пакета из канала системы; вычисление небыстрое, поэтому ответ помнится полдня
nixver() {
  local f v
  f="$CACHE/ver-$(printf '%s' "$1" | tr -c 'A-Za-z0-9' _)"
  if [ -n "$(find "$f" -mmin -720 2>/dev/null)" ]; then cat "$f"; return; fi
  v="$(timeout 60 nix-instantiate --eval --strict -E "(import <nixpkgs> { config.allowUnfree = true; }).$1" 2>/dev/null | tr -d '"')"
  mkdir -p "$CACHE"; [ -n "$v" ] && printf '%s' "$v" > "$f"
  printf '%s' "$v"
}
newer() { [ -n "$1" ] && [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n 1)" = "$1" ]; }
orow() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4"; }

list_optional() {
  local cur latest stable beta nv=0
  if has nvidia-open || has nvidia-closed; then nv=1; fi
  cur="$(uname -r | sed 's/[-+].*//')"
  if opt kernel-latest; then
    orow kernel-latest applied "Самое новое ядро Linux" "сейчас $cur; обновляется вместе с системой"
  else
    case "$NVIDIA_VARIANT" in
      lts*) ;;   # под драйвер NVIDIA выбрано ядро с долгой поддержкой: новое предлагать незачем
      *) latest="$(nixver linuxPackages_latest.kernel.version)"
         if newer "$latest" "$cur"; then
           orow kernel-latest offer "Ядро Linux $latest" "сейчас $cur. В новом ядре свежие драйверы для всех устройств. Нужна перезагрузка$([ "$nv" -eq 1 ] && printf '. Драйвер NVIDIA под новое ядро собирается не всегда: тогда всё останется как было')"
         fi ;;
    esac
  fi
  if [ "$nv" -eq 1 ]; then
    if [ "$NVIDIA_VARIANT" = beta ]; then
      orow nvidia-beta applied "Драйвер NVIDIA: предварительная версия" "ставится вместо обычной"
    elif [ "$NVIDIA_VARIANT" = stable ]; then
      stable="$(nixver linuxPackages.nvidiaPackages.stable.version)"; beta="$(nixver linuxPackages.nvidiaPackages.beta.version)"
      newer "$beta" "$stable" && orow nvidia-beta offer "Драйвер NVIDIA $beta (предварительная версия)" "сейчас $stable. Новее, но проверен меньше"
    fi
  fi
  if opt firmware-all; then
    orow firmware-all applied "Полный набор прошивок устройств" "включая несвободные, если они разрешены в системе"
  elif journalctl -k -b --no-pager 2>/dev/null | grep -qiE 'firmware.*(failed|error -2)'; then
    orow firmware-all offer "Полный набор прошивок устройств" "ядро искало прошивку для устройства и не нашло её"
  fi
}

has() { [ -n "${FEATURE[$1]:-}" ]; }
plan() {
  [ "${#FEATURE[@]}" -gt 0 ] || [ "${#OPT[@]}" -gt 0 ] || return 0
  echo "# Драйверы, подобранные под это оборудование командой win11-drivers."
  echo "# Файл создаётся заново при каждом подборе - не правьте его вручную."
  echo "{ config, lib, pkgs, ... }:"
  echo "{"
  local f
  for f in $(printf '%s\n' "${!FEATURE[@]}" | sort); do echo "  # feature: $f"; done
  for f in $(printf '%s\n' "${!OPT[@]}" | sort); do echo "  # optional: $f"; done
  # приоритет 90: сильнее обычной строки в configuration.nix, слабее ядра под драйвер NVIDIA
  opt kernel-latest && echo '  boot.kernelPackages = lib.mkOverride 90 pkgs.linuxPackages_latest;'
  if opt firmware-all; then
    echo '  hardware.enableRedistributableFirmware = true;'
    echo '  hardware.enableAllFirmware = config.nixpkgs.config.allowUnfree or false;'
  fi
  if has nvidia-open || has nvidia-closed; then
    echo '  services.xserver.videoDrivers = lib.mkDefault [ "nvidia" ];'
    echo '  hardware.nvidia.modesetting.enable = lib.mkDefault true;'
    local open=false
    has nvidia-open && [ "$NVIDIA_VARIANT" != lts-closed ] && open=true
    echo "  # nvidia-variant: $NVIDIA_VARIANT"
    echo "  hardware.nvidia.open = lib.mkDefault $open;"
    echo '  hardware.graphics.enable = lib.mkDefault true;'
    case "$NVIDIA_VARIANT" in
      beta) echo '  hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.beta;' ;;
      lts*) echo '  boot.kernelPackages = lib.mkForce pkgs.linuxPackages;' ;;
    esac
  fi
  if has nvidia-prime; then
    set -- ${FEATURE[nvidia-prime]}
    echo "  hardware.nvidia.prime = {"
    echo "    offload.enable = lib.mkDefault true;"
    echo "    offload.enableOffloadCmd = lib.mkDefault true;"
    echo "    ${1}BusId = \"$2\";"
    echo "    nvidiaBusId = \"$3\";"
    echo "  };"
  fi
  has intel-media && echo '  hardware.graphics.extraPackages = [ pkgs.intel-media-driver pkgs.intel-vaapi-driver pkgs.libvdpau-va-gl ];'
  has amdgpu-pro && echo '  hardware.graphics.extraPackages = [ pkgs.rocmPackages.clr.icd ];'
  local mods=""
  if has broadcom-sta; then
    mods+=" config.boot.kernelPackages.broadcom_sta"
    echo '  boot.kernelModules = [ "wl" ];'
    echo '  boot.blacklistedKernelModules = [ "b43" "bcma" "ssb" "brcmsmac" ];'
    echo '  nixpkgs.config.allowInsecurePredicate = pkg: lib.hasPrefix "broadcom-sta" (lib.getName pkg);'
  fi
  for f in rtl88x2bu rtl8821cu rtl8812au rtl8821au rtl8814au rtw89 rtw88 digimend zenpower; do
    has "$f" && mods+=" config.boot.kernelPackages.$f"
  done
  [ -n "$mods" ] && echo "  boot.extraModulePackages = [$mods ];"
  has zenpower && echo '  boot.blacklistedKernelModules = [ "k10temp" ]; boot.kernelModules = [ "zenpower" ];'
  has vbox && echo '  virtualisation.virtualbox.guest.enable = lib.mkDefault true;'
  has vmware && echo '  virtualisation.vmware.guest.enable = lib.mkDefault true;'
  if has qemu; then
    echo '  services.qemuGuest.enable = lib.mkDefault true;'
    echo '  services.spice-vdagentd.enable = lib.mkDefault true;'
  fi
  has hyperv && echo '  virtualisation.hypervGuest.enable = lib.mkDefault true;'
  has fprintd && echo '  services.fprintd.enable = lib.mkDefault true;'
  has sof-firmware && echo '  hardware.firmware = [ pkgs.sof-firmware pkgs.alsa-firmware ];'
  has hp-plugin && echo '  services.printing.drivers = [ (pkgs.hplipWithPlugin.override { withPlugin = true; }) ];'
  has brlaser && echo '  services.printing.drivers = [ pkgs.brlaser ];'
  has cups-bjnp && echo '  services.printing.drivers = [ pkgs.cups-bjnp ];'
  has sane-airscan && echo '  hardware.sane.extraBackends = [ pkgs.sane-airscan ];'
  echo "}"
}

pending() { [ "$(plan)" != "$(cat "$TARGET" 2>/dev/null)" ]; }

backup() {
  sudo rm -f "$TARGET.prev"
  [ -e "$TARGET" ] && sudo cp "$TARGET" "$TARGET.prev"
  return 0
}
put() {
  local new; new="$(plan)"
  if [ -n "$new" ]; then printf '%s\n' "$new" | sudo tee "$TARGET" >/dev/null
  else sudo rm -f "$TARGET"; fi
}
write() { backup; put; }
restore() {
  if [ -e "$TARGET.prev" ]; then sudo mv "$TARGET.prev" "$TARGET"; else sudo rm -f "$TARGET"; fi
}

install_single() {
  local feat="$1"
  [ -n "$feat" ] || { echo "Не указан драйвер для установки"; return 1; }
  echo "== Подготовка установки драйвера: $feat =="

  detect
  case "$feat" in
    hp-plugin)
      need hp-plugin
      sudo rm -f /etc/nixos/win11-shell/no-hp-plugin 2>/dev/null || true
      ;;
    firmware-all)
      OPT["firmware-all"]=1
      ;;
    kernel-latest)
      OPT["kernel-latest"]=1
      ;;
    nvidia-beta)
      WIN11_NVIDIA=beta
      need nvidia-open
      ;;
    nvidia-lts)
      WIN11_NVIDIA=lts
      need nvidia-open
      ;;
    nvidia-open)
      need nvidia-open
      ;;
    nvidia-closed)
      need nvidia-closed
      ;;
    nvidia*)
      has nvidia-open || has nvidia-closed || need nvidia-open
      ;;
    fwupd)
      echo "Обновление прошивок устройств через LVFS / fwupd..."
      if command -v fwupdmgr >/dev/null 2>&1; then
        fwupdmgr refresh --force || true
        fwupdmgr update -y && return 0
      fi
      ;;
    *)
      need "$feat"
      ;;
  esac

  mkdir -p "$STATE"
  backup
  put || return 1

  echo "Сборка и применение конфигурации системы с драйвером $feat..."
  local log="${XDG_CACHE_HOME:-$HOME/.cache}/win11-shell/update.log"
  mkdir -p "$(dirname "$log")"
  if win11-update >> "$log" 2>&1; then
    sudo rm -f "$TARGET.prev"
    case "$feat" in
      nvidia*|kernel-latest|broadcom-sta|rtl*)
        echo "Драйвер ядра успешно установлен. Рекомендуется перезагрузить компьютер."
        ;;
      *)
        echo "Драйвер успешно установлен и применён на лету."
        ;;
    esac
    return 0
  else
    echo "Сборка с драйвером $feat завершилась с ошибкой. Подробности: $log"
    echo "Откатываю изменения конфигурации..."
    restore
    return 1
  fi
}

cmd="${1:-detect}"
case "$cmd" in
  detect|plan|status|apply|write|nvidia|optional|search|install) detect ;;
esac
case "$cmd" in
  detect) printf '%s' "$ROWS" ;;
  search)
    echo "== Поиск драйверов по оборудованию и источникам NixOS =="
    printf '%s' "$ROWS" | awk -F'\t' '{
      st = $5;
      st_ru = (st == "install" ? "доступен для установки" : (st == "applied" ? "установлен" : (st == "ok" ? "активен (в ядре)" : (st == "offer" ? "рекомендуется" : (st == "update" ? "доступно обновление" : "не найден")))));
      printf " • [%s] %s: %s\n   Драйвер: %s (%s)\n   Источник: %s\n\n", $2, $3, st_ru, $4, $6, $7
    }'
    ;;
  install)
    feat="${2:-}"
    [ -n "$feat" ] || { echo "Укажите драйвер для установки: win11-drivers install <имя>"; exit 1; }
    install_single "$feat"
    ;;
  plan) plan ;;
  status) if pending; then echo pending; else echo ok; fi ;;
  write) pending && write ;;
  restore) restore ;;
  optional)
    name="${2:-}"
    [ -n "$name" ] || { list_optional; exit 0; }
    case "$name" in kernel-latest|nvidia-beta|firmware-all) ;; *) echo "Нет такого: $name. Есть: kernel-latest, nvidia-beta, firmware-all" >&2; exit 1 ;; esac
    want="${3:-on}"
    if [ "$name" = nvidia-beta ]; then
      WIN11_NVIDIA="$([ "$want" = on ] && echo beta || echo stable)" exec bash "$0" apply
    fi
    if [ "$want" = on ]; then OPT["$name"]=1; else unset "OPT[$name]"; fi
    pending || { echo "Уже так и есть."; exit 0; }
    backup; put || exit 1
    if win11-update; then
      sudo rm -f "$TARGET.prev"
      [ "$name" = kernel-latest ] && echo "Ядро изменено: перезагрузите компьютер."
      exit 0
    fi
    echo "Сборка не удалась - возвращаю прежний набор драйверов."
    restore; exit 1 ;;
  nvidia)
    case " $NVIDIA_VARIANTS " in
      *" ${2:-} "*) WIN11_NVIDIA="$2" exec bash "$0" apply ;;
      *) echo "Сейчас: $NVIDIA_VARIANT. Варианты: $NVIDIA_VARIANTS"; echo "Выбрать: win11-drivers nvidia lts" ;;
    esac ;;
  apply)
    # Для всех строк с состоянием install активируем need
    while IFS="$T" read -r fid fclass fname fdrv fst fnote fsrc; do
      if [ "$fst" = "install" ] || [ "$fst" = "update" ]; then
        case "$fid" in
          nvidia*) has nvidia-open || has nvidia-closed || need nvidia-open ;;
          hp-plugin) need hp-plugin; sudo rm -f /etc/nixos/win11-shell/no-hp-plugin 2>/dev/null || true ;;
          fwupd) command -v fwupdmgr >/dev/null 2>&1 && fwupdmgr refresh --force >/dev/null 2>&1 && fwupdmgr update -y >/dev/null 2>&1 || true ;;
          *) [ -n "$fid" ] && need "$fid" ;;
        esac
      fi
    done <<< "$ROWS"

    pending || { echo "Все подобранные драйверы уже установлены."; exit 0; }
    echo "Будут установлены:"
    printf '%s' "$ROWS" | awk -F'\t' '$5 == "install" || $5 == "update" { print "  • " $2 ": " $3 " (" $7 ") - " $6 }'
    mkdir -p "$STATE"; : > "$BUILD_LOG"
    backup
    # без NVIDIA вариант один; с ней перебираем от выбранного к самому надёжному
    tries="$NVIDIA_VARIANT"
    if has nvidia-open || has nvidia-closed; then
      [ -n "${WIN11_NVIDIA:-}" ] || tries="$(printf '%s\n' $NVIDIA_AUTO | sed -n "/^$NVIDIA_VARIANT\$/,\$p" | tr '\n' ' ')"
    fi
    [ -n "$tries" ] || tries="$NVIDIA_VARIANT"
    # Ctrl+C в окне - это отмена, а не "вариант не собрался": перебор останавливается
    stopped=0; trap 'stopped=1' INT
    for NVIDIA_VARIANT in $tries; do
      if has nvidia-open || has nvidia-closed; then echo; echo "== Драйвер NVIDIA, вариант: $NVIDIA_VARIANT =="; fi
      put || exit 1
      echo "--- вариант $NVIDIA_VARIANT, $(date '+%F %T')" >> "$BUILD_LOG"
      win11-update 2>&1 | tee -a "$BUILD_LOG"
      if [ "${PIPESTATUS[0]}" -eq 0 ]; then
        sudo rm -f "$TARGET.prev"
        case "$NVIDIA_VARIANT" in lts*) echo "Ядро заменено на ядро с долгой поддержкой: перезагрузите компьютер." ;; esac
        exit 0
      fi
      if [ "$stopped" -eq 1 ]; then
        echo; echo "Установка прервана (нажато Ctrl+C). Возвращаю прежний набор драйверов."
        echo "Чтобы скопировать текст из этого окна, используйте Ctrl+Shift+C."
        restore; exit 130
      fi
      echo "Сборка не удалась (вариант $NVIDIA_VARIANT)."
    done
    echo "Ни один вариант не собрался - возвращаю прежний набор. Журнал: $BUILD_LOG"
    restore; exit 1 ;;
  reset) FEATURE=(); write; echo "Подобранные драйверы убраны. Пересоберите систему: win11-update" ;;
  *) sed -n '1,12p' "$0" | sed 's/^# \{0,1\}//' ;;
esac
