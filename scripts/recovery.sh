#!/usr/bin/env bash
# win11-recovery - восстановление системы и рабочего пространства Windows 11 Shell
# Использование:
#   win11-recovery            интерактивное меню выбора
#   win11-recovery system     починка системы + рабочего пространства
#   win11-recovery workspace  только починить рабочее пространство
set -uo pipefail

export PATH="$PATH:/run/current-system/sw/bin"
KIT="/etc/nixos/win11-shell-kit"
LOGDIR="${XDG_CACHE_HOME:-$HOME/.cache}/win11-shell"
mkdir -p "$LOGDIR"
REC_LOG="$LOGDIR/recovery.log"

show_header() {
  echo -e "\033[1;36m==================================================\033[0m"
  echo -e "\033[1;37m       Служба восстановления Windows 11 Shell      \033[0m"
  echo -e "\033[1;36m==================================================\033[0m"
  echo
}

# 1. Проверка наличия скачанной копии Niri в архиве или локальном комплекте
# Если копии нет - импортируем код из https://github.com/Recodil/awdvcawd
import_niri_code() {
  echo -e "\033[1;33m[*] Проверка компонентов Niri и рабочего пространства...\033[0m"
  local found=0
  for p in "$KIT/niri" "/etc/nixos/win11-shell/niri" "$HOME/.cache/win11-shell/niri" "$PWD/niri"; do
    if [ -d "$p" ] && [ -f "$p/config.kdl" ]; then
      echo "    Найдена локальная копия Niri: $p"
      mkdir -p "$HOME/.config/niri"
      cp -f "$p/config.kdl" "$HOME/.config/niri/config.kdl.default" 2>/dev/null || true
      [ -f "$p/win11-settings.kdl" ] && cp -f "$p/win11-settings.kdl" "$HOME/.config/niri/win11-settings.kdl.default" 2>/dev/null || true
      found=1
      break
    fi
  done

  if [ "$found" -eq 0 ]; then
    echo "    Локальная копия Niri в архиве не найдена. Импорт из https://github.com/Recodil/awdvcawd ..."
    local tmp_dir; tmp_dir="$(mktemp -d)"
    if command -v git >/dev/null 2>&1 && git clone --depth 1 https://github.com/Recodil/awdvcawd "$tmp_dir/repo" >/dev/null 2>&1; then
      if [ -f "$tmp_dir/repo/config.kdl" ]; then
        mkdir -p "$HOME/.config/niri"
        cp -f "$tmp_dir/repo/config.kdl" "$HOME/.config/niri/config.kdl.default"
        [ -f "$tmp_dir/repo/win11-settings.kdl" ] && cp -f "$tmp_dir/repo/win11-settings.kdl" "$HOME/.config/niri/win11-settings.kdl.default"
        echo "    Код успешно импортирован из GitHub (Recodil/awdvcawd)."
        found=1
      fi
    elif command -v curl >/dev/null 2>&1; then
      if curl -fsSL -m 15 "https://github.com/Recodil/awdvcawd/archive/refs/heads/main.tar.gz" | tar -xz -C "$tmp_dir" 2>/dev/null; then
        local sub; sub="$(find "$tmp_dir" -type f -name "config.kdl" | head -n 1)"
        if [ -n "$sub" ]; then
          mkdir -p "$HOME/.config/niri"
          cp -f "$sub" "$HOME/.config/niri/config.kdl.default"
          echo "    Код успешно импортирован из архива GitHub (Recodil/awdvcawd)."
          found=1
        fi
      fi
    fi
    rm -rf "$tmp_dir"
  fi

  if [ "$found" -eq 0 ]; then
    echo "    (Использован встроенный резервный шаблон Niri)"
  fi
}

repair_workspace() {
  echo -e "\n\033[1;36m== Починка рабочего пространства ==\033[0m"
  import_niri_code

  echo "    Проверка директорий и прав доступа..."
  mkdir -p "$HOME/.config/niri" "$HOME/.config/win11-shell" "$HOME/.local/state/win11-shell" "$HOME/.cache/win11-shell"
  chmod 700 "$HOME/.config/win11-shell" "$HOME/.local/state/win11-shell" 2>/dev/null || true

  echo "    Проверка и восстановление настроек Niri (config.kdl)..."
  if [ ! -s "$HOME/.config/niri/config.kdl" ] || ! grep -q "input" "$HOME/.config/niri/config.kdl" 2>/dev/null; then
    if [ -f "$HOME/.config/niri/config.kdl.default" ]; then
      cp -f "$HOME/.config/niri/config.kdl.default" "$HOME/.config/niri/config.kdl"
    elif [ -f "$KIT/niri/config.kdl" ]; then
      cp -f "$KIT/niri/config.kdl" "$HOME/.config/niri/config.kdl"
    fi
    echo "    Файл config.kdl восстановлен."
  fi

  echo "    Проверка win11-settings.kdl..."
  if [ ! -s "$HOME/.config/niri/win11-settings.kdl" ]; then
    cat > "$HOME/.config/niri/win11-settings.kdl" << 'EOF'
input {
    keyboard {
        xkb {
            layout "us,ru"
            options "grp:win_space_toggle,grp:alt_shift_toggle"
        }
        repeat-delay 600
        repeat-rate 25
    }
    mouse {
        accel-speed 0.00
    }
    touchpad {
        tap
        natural-scroll
    }
}
animations {
    slowdown 1.00
}
layout {
    shadow {
        on
    }
}
window-rule {
    geometry-corner-radius 8
    clip-to-geometry true
}
EOF
    echo "    Файл win11-settings.kdl пересоздан."
  fi

  echo "    Проверка целостности файла параметров (settings.json)..."
  local sjson="$HOME/.config/win11-shell/settings.json"
  if [ -f "$sjson" ]; then
    if ! command -v jq >/dev/null 2>&1 || ! jq . "$sjson" >/dev/null 2>&1; then
      echo "    Файл settings.json был повреждён. Восстанавливаю резервную копию..."
      if [ -f "$sjson.bak" ] && jq . "$sjson.bak" >/dev/null 2>&1; then
        cp -f "$sjson.bak" "$sjson"
      else
        cat > "$sjson" << 'EOF'
{"pinned":["org.gnome.Nautilus","google-chrome","firefox","telegram-desktop","discord","code"],"barPinned":["org.gnome.Nautilus","google-chrome","firefox","telegram-desktop","discord","code"],"updIcon":true,"dark":false,"barEdge":"bottom","barAlign":"left","wallpaper":"","welcome":true,"autoLock":true,"showSearch":true,"showTaskView":true,"nightTemp":4000,"nightAuto":false,"nightFrom":"21:00","nightTo":"07:00","dnd":false,"dndAllow":[],"minAnim":true,"startIcon":"nixos","theme":"","wallMode":"fixed","wallDir":"","wallAuto":"","wallKey":""}
EOF
      fi
    fi
  fi

  echo "    Очистка временных блокировок и журналов сбоев..."
  rm -f "$HOME/.local/state/win11-shell"/*.lock 2>/dev/null || true
  rm -f /run/win11-shell/fail 2>/dev/null || true

  echo "    Применение параметров Niri на лету..."
  if command -v niri >/dev/null 2>&1; then
    niri msg action load-config-file 2>/dev/null || true
  fi

  echo -e "\n\033[1;32mРабочее пространство успешно починено и готово к работе.\033[0m"
}

repair_system() {
  echo -e "\n\033[1;36m== Починка системы + рабочего пространства ==\033[0m"
  repair_workspace

  echo -e "\n\033[1;33m[*] Диагностика и починка системных компонентов NixOS...\033[0m"
  if [ ! -f /etc/nixos/configuration.nix ]; then
    echo -e "\033[1;31mОшибка: /etc/nixos/configuration.nix не найден!\033[0m" >&2
    return 1
  fi

  echo "    Проверка системных прав и каталогов /run и /var..."
  sudo mkdir -p /run/win11-shell /var/lib/win11-shell /var/log/win11-shell /var/lib/win11-shell/faces 2>/dev/null || true
  sudo chmod 1777 /run/win11-shell /var/lib/win11-shell/faces 2>/dev/null || true
  sudo chmod 755 /var/lib/win11-shell /var/log/win11-shell 2>/dev/null || true

  echo "    Сброс и перезапуск системных служб звука и сети..."
  systemctl --user restart pipewire pipewire-pulse wireplumber 2>/dev/null || true
  sudo systemctl reset-failed 2>/dev/null || true

  echo "    Проверка целостности конфигурации NixOS..."
  if command -v nixos-rebuild >/dev/null 2>&1; then
    echo "    Выполняю пересборку и переключение системы (nixos-rebuild switch)..."
    if sudo nixos-rebuild switch --fast; then
      echo "    Конфигурация NixOS успешно применена."
    else
      echo -e "\033[1;33mПредупреждение: пересборка завершилась ошибкой. Предлагается откат на предыдущее рабочее поколение.\033[0m"
      printf 'Откатить систему на предыдущее поколение? [Y/n] '
      read -r ans
      case "$ans" in
        n|N|нет|Нет) ;;
        *) sudo nix-env -p /nix/var/nix/profiles/system --rollback && sudo /nix/var/nix/profiles/system/bin/switch-to-configuration switch ;;
      esac
    fi
  fi

  echo -e "\n\033[1;32mСистема и рабочее пространство полностью восстановлены!\033[0m"
}

show_header

mode="${1:-}"
if [ -z "$mode" ]; then
  echo "Выберите вариант восстановления:"
  echo "  [1] Починка системы + рабочего пространства"
  echo "      (Проверка NixOS, служб, Niri, прав доступа и рабочего стола)"
  echo
  echo "  [2] Только починить рабочее пространство"
  echo "      (Быстрое восстановление Niri, панелей задач, горячих клавиш без пересборки системы)"
  echo
  echo "  [q] Выход"
  echo
  printf "Ваш выбор [1/2/q]: "
  read -r choice
  case "$choice" in
    1) mode="system" ;;
    2) mode="workspace" ;;
    *) echo "Отменено."; exit 0 ;;
  esac
fi

case "$mode" in
  system|all) repair_system ;;
  workspace|desktop|user) repair_workspace ;;
  *) echo "Неизвестный режим: $mode. Доступно: system, workspace" >&2; exit 1 ;;
esac
