#!/usr/bin/env bash
# Собирает всё нужное для разбора сбоя в один файл: bash doctor.sh
OUT="$HOME/win11-report.txt"
sec() { echo; echo "===== $1 ====="; }
{
  sec "система"; nixos-version; uname -r
  echo "оболочка:    версия $(cat /etc/nixos/win11-shell/scripts/version 2>/dev/null || echo "до 14.11.2026 (без номера)")"
  echo "загружена:   $(readlink -f /run/current-system)"
  echo "по умолчанию: $(readlink -f /nix/var/nix/profiles/system)"
  sec "поколения"; sudo nix-env -p /nix/var/nix/profiles/system --list-generations | tail -n 8
  sec "пробный запуск"
  sudo cat /var/lib/win11-shell/last-result 2>/dev/null || echo "нет результата"
  sudo cat /var/lib/win11-shell/trial 2>/dev/null
  ls /etc/nixos/win11-shell/ 2>/dev/null
  sec "последний журнал сбоя"
  last="$(sudo sh -c 'ls -t /var/log/win11-shell/fail-*.log 2>/dev/null | head -n 1')"
  if [ -n "$last" ]; then echo "$last"; sudo cat "$last"; else echo "нет"; fi
  sec "предыдущие журналы сбоев (кратко)"
  sudo sh -c 'ls -t /var/log/win11-shell/fail-*.log 2>/dev/null | sed -n 2,4p' | while read -r f; do
    echo "--- $f"; sudo head -n 3 "$f"; sudo sed -n '/shell.log ==/,$p' "$f" | tail -n 40
  done
  sec "сбои обновления на лету"
  for f in $(ls -t "$HOME"/.local/state/win11-shell/hot-fail-*.log 2>/dev/null | head -n 2); do echo "--- $f"; tail -n 60 "$f"; done
  sec "журнал оболочки прошлого сеанса"; tail -n 60 "$HOME/.local/state/win11-shell/shell.log.old" 2>/dev/null || echo "нет"
  [ -f "$HOME/win11-shell-qml-error.log" ] && { sec "ошибка загрузки QML"; tail -n 40 "$HOME/win11-shell-qml-error.log"; }
  sec "сбойные службы"; systemctl --failed --no-pager
  sec "экран входа"; systemctl status display-manager.service --no-pager -n 30
  sec "ошибки этой загрузки"; sudo journalctl -b -p err --no-pager | tail -n 60
  sec "ошибки прошлой загрузки"; sudo journalctl -b -1 -p err --no-pager | tail -n 60
  sec "экран входа, прошлая загрузка"; sudo journalctl -b -1 -u display-manager.service --no-pager | tail -n 60
  sec "zapret (YouTube, Discord)"
  if command -v win11-zapret >/dev/null; then win11-zapret 2>&1 | sed "s/\x1b\[[0-9;]*m//g"; else echo "win11-zapret не установлен"; fi
  sec "память"
  if command -v win11-mem >/dev/null; then win11-mem; else free -m; fi
  sec "кнопка \"Свернуть\""
  if command -v win11-minimize >/dev/null; then win11-minimize --check; else echo "win11-minimize не установлен"; fi
  sec "конфиг niri"
  if command -v niri >/dev/null; then niri validate -c "$HOME/.config/niri/config.kdl"; else echo "niri не установлен в этой системе"; fi
  sec "журнал оболочки"; tail -n 80 "$HOME/.local/state/win11-shell/shell.log" 2>/dev/null || echo "нет"
  sec "память"; free -m
  sec "звук"
  if command -v win11-sound >/dev/null; then win11-sound 2>&1; else cat /proc/asound/cards 2>&1; fi
  sec "материнская плата"
  cat /sys/class/dmi/id/board_vendor /sys/class/dmi/id/board_name /sys/class/dmi/id/product_name 2>/dev/null
  sec "падения программ (coredump)"
  coredumpctl list --no-pager --since "-3 days" 2>&1 | tail -n 15
  coredumpctl info --no-pager quickshell 2>/dev/null | grep -vE '^\s*$' | head -n 45
  coredumpctl info --no-pager qs 2>/dev/null | grep -vE '^\s*$' | head -n 45
  sec "сборка драйверов"
  tail -n 60 "$HOME/.local/state/win11-shell/drivers-build.log" 2>/dev/null || echo "нет"
  sec "оборудование и драйверы"
  if command -v lspci >/dev/null; then lspci -k; else echo "lspci не установлен"; fi
  sec "прошивки, которые не загрузились"
  sudo journalctl -b -k --no-pager | grep -iE 'firmware.*(fail|error|not found)|failed to load' | tail -n 30
} > "$OUT" 2>&1
echo "Готово: $OUT - пришлите этот файл."
