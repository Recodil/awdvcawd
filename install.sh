#!/usr/bin/env bash
# Установка оболочки Win11 с самопроверкой и автоматическим возвратом.
#   bash install.sh            обычная установка (без sudo - пароль спросит сам)
#   bash install.sh --safe     экран входа LightDM, без заставки загрузки
#   bash install.sh --normal   обычный режим, даже если прошлая попытка не удалась
#   bash install.sh --check    только проверки и сборка, систему не трогать
#   bash install.sh --rebuild  пересобрать из того, что уже лежит в /etc/nixos (так работает win11-update)
#   bash install.sh --system   перед сборкой обновить пакеты NixOS (nix-channel --update)
#   bash install.sh --no-niri-patch  не пересобирать niri (кнопка "Свернуть" в заголовках окон работать не будет)
#   bash install.sh --full     всегда с перезапуском экрана входа, даже если можно обновить на лету
#
# Ваш /etc/nixos/configuration.nix не заменяется. При первой установке он переименовывается
# в configuration-base.nix, а новый configuration.nix из трёх строк подключает его и оболочку.
set -uo pipefail

if [ "$(id -u)" -eq 0 ]; then
  echo "Запустите без sudo: bash install.sh" >&2
  exit 1
fi

SAFE=0; FORCE_NORMAL=0; CHECK_ONLY=0; REBUILD=0; SYSTEM=0; FULL=0; NOPATCH=0; GENERIC=0; ASK=0; VERBOSE=0
for a in "$@"; do
  case "$a" in
    --safe) SAFE=1 ;;
    --normal) FORCE_NORMAL=1 ;;
    --check) CHECK_ONLY=1 ;;
    --rebuild) REBUILD=1 ;;
    --system) SYSTEM=1 ;;
    --full) FULL=1 ;;
    --no-niri-patch) NOPATCH=1 ;;
    --ask) ASK=1 ;;
    --verbose) VERBOSE=1 ;;
    *) echo "Неизвестный параметр: $a" >&2; exit 1 ;;
  esac
done

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
STATE=/var/lib/win11-shell
STAGE="$HOME/.cache/win11-shell/stage"
PROFILE=/nix/var/nix/profiles/system
CUR="$(readlink -f /run/current-system)"
KIT=/etc/nixos/win11-shell-kit
if [ "$REBUILD" -eq 1 ]; then
  CONF=/etc/nixos/configuration.nix; MOD=/etc/nixos/win11-shell; NIRI_CFG="$HOME/.config/niri/config.kdl"
  [ -d "$MOD" ] || { echo "В /etc/nixos нет установленной оболочки - запустите обычный bash install.sh" >&2; exit 1; }
else
  MOD=""; NIRI_CFG="$SRC/niri/config.kdl"
  [ -r /etc/nixos/configuration.nix ] || { echo "Нет /etc/nixos/configuration.nix - это не NixOS или система настроена нестандартно." >&2; exit 1; }
  if [ -e /etc/nixos/flake.nix ]; then
    echo "Система настроена через flake (/etc/nixos/flake.nix). Установщик работает с обычным configuration.nix;" >&2
    echo "подключите модуль вручную: imports = [ ./win11-shell/win11-shell.nix ./win11-shell/base.nix ]; (файлы - в этой папке)." >&2
    exit 1
  fi
  if grep -q 'win11-shell/win11-shell.nix' /etc/nixos/configuration.nix; then
    # оболочка уже подключена - конфиг не трогаем, обновляются только файлы оболочки
    CONF=/etc/nixos/configuration.nix
  else
    # первая установка на этом компьютере: прежний конфиг остаётся как configuration-base.nix
    GENERIC=1
    CONF="$HOME/.cache/win11-shell/configuration.nix"
    mkdir -p "$HOME/.cache/win11-shell"
    cat > "$CONF" <<EOF
# Создан установщиком оболочки Win11 ($(date '+%F %T')).
# Ваш прежний configuration.nix лежит рядом как configuration-base.nix - правьте его, как раньше.
# Чтобы убрать оболочку: верните configuration-base.nix на место этого файла и выполните sudo nixos-rebuild switch.
{ ... }:
{
  imports = [ ./configuration-base.nix ./win11-shell/win11-shell.nix ./win11-shell/base.nix ];
  users.users."$USER".extraGroups = [ "networkmanager" "lp" "scanner" "video" ];
}
EOF
  fi
fi

ERRORS=0; WARNS=0
ok()   { echo "  [ok]   $1"; }
bad()  { echo "  [СБОЙ] $1" >&2; ERRORS=$((ERRORS + 1)); }
warn() { echo "  [!]    $1"; WARNS=$((WARNS + 1)); }
die()  { echo; echo "$1" >&2; echo "Система не изменена." >&2; exit 1; }

mkdir -p "$HOME/.cache/win11-shell"
echo "==> 0. Результат прошлой попытки"
sudo -v || exit 1
if sudo test -f "$STATE/trial"; then
  TNEW="$(sudo sed -n 's/^NEW=//p' "$STATE/trial")"
  TMODE="$(sudo sed -n 's/^MODE=//p' "$STATE/trial")"
  if [ "$TNEW" != "$CUR" ] && [ "$(readlink -f "$PROFILE")" = "$TNEW" ]; then
    # прошлая установка ждёт перезагрузки; эта её заменит
    echo "    прошлая установка ещё не включена (ждала перезагрузки) - собираю заново"
  elif [ "$TNEW" != "$CUR" ]; then
    echo "failed mode=$TMODE reason=перезагрузка во время проверки" | sudo tee "$STATE/last-result" >/dev/null
  fi
  sudo rm -f "$STATE/trial"
fi
LAST="$(sudo cat "$STATE/last-result" 2>/dev/null || true)"
if [ -n "$LAST" ]; then
  echo "    $LAST"
else
  echo "    нет данных"
fi
# Безопасный режим меняет только экран входа, поэтому включается сам лишь тогда,
# когда в прошлый раз не запустился именно он. Сбой оболочки он не лечит.
case "$LAST" in
  failed*mode=normal*"экран входа"*)
    if [ "$SAFE" -eq 0 ] && [ "$FORCE_NORMAL" -eq 0 ] && [ "$REBUILD" -eq 0 ]; then
      SAFE=1
      echo "    Обычный режим в прошлый раз не заработал - включаю безопасный (как --safe)."
    fi ;;
esac
if [ "$SAFE" -eq 1 ]; then MODE=safe; else MODE=normal; fi

# Пробный запуск новой оболочки рядом с работающей: ошибка в QML видна сразу, до долгой сборки.
# На несколько секунд появляется вторая панель задач - это нормально.
preflight_shell() {
  [ -n "${WAYLAND_DISPLAY:-}" ] && command -v qs >/dev/null 2>&1 || return 0
  local log pid i=0
  log="$(mktemp)"
  qs -p "$SRC/shell" > "$log" 2>&1 &
  pid=$!
  while [ "$i" -lt 20 ]; do
    grep -q 'Configuration Loaded\|Failed to load configuration' "$log" && break
    kill -0 "$pid" 2>/dev/null || break
    sleep 1; i=$((i + 1))
  done
  sleep 2
  kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
  # провалом считаем только явный отказ загрузить конфигурацию; всё прочее не мешает установке
  if ! grep -q 'Failed to load configuration' "$log"; then
    ok "новая оболочка загружается на этом компьютере"
    # ошибки, которые не мешают загрузке, но о которых стоит знать
    grep -E 'ERROR|TypeError|ReferenceError|is not a type|Cannot assign' "$log" | sed 's/\x1b\[[0-9;]*m//g' | head -n 8 | sed 's/^/         /'
  else
    bad "новая оболочка не загружается. Сообщение Quickshell:"
    sed 's/\x1b\[[0-9;]*m//g' "$log" | grep -v '^ *$' | tail -n 25 | sed 's/^/         /' >&2
    cp "$log" "$HOME/win11-shell-qml-error.log" 2>/dev/null && echo "         полный текст: ~/win11-shell-qml-error.log" >&2
  fi
  rm -f "$log"
}

# Первая установка на этом компьютере (или --ask): что именно ставить, решает пользователь.
ANSWERS=""
answer() { [ -n "$ANSWERS" ] && sed -n "s/^$1=//p" "$ANSWERS" | head -n 1; }
if [ "$REBUILD" -eq 0 ] && [ -t 0 ] && { [ "$ASK" -eq 1 ] || [ ! -d /etc/nixos/win11-shell ]; }; then
  ANSWERS="$HOME/.cache/win11-shell/answers"
  mkdir -p "$HOME/.cache/win11-shell"
  bash "$SRC/scripts/setup-questions.sh" "$ANSWERS" || ANSWERS=""
  [ "$(answer minimize)" = 0 ] && NOPATCH=1
fi

[ -r "$SRC/scripts/version" ] && echo "    версия оболочки в архиве: $(cat "$SRC/scripts/version")"
echo "==> 1. Проверка файлов"
[ "$REBUILD" -eq 1 ] || preflight_shell
if [ "$REBUILD" -eq 1 ]; then
  nix-instantiate --parse "$CONF" >/dev/null || bad "синтаксис /etc/nixos/configuration.nix"
  [ -s "$NIRI_CFG" ] || bad "нет $NIRI_CFG"
else
for f in win11-shell.nix base.nix printing.nix scripts/shutdown.sh scripts/printfix.sh scripts/lists.sh scripts/pack.sh scripts/drivers.sh scripts/updates.sh scripts/recovery.sh recovery.nix disk.nix drivers.nix niri-patch.nix niri-minimize.rs scripts/minimize.sh zapret.nix scripts/zapret.sh scripts/zapret-run.sh scripts/zapret-root.sh scripts/taskmgr.sh update.sh niri/config.kdl niri/win11-settings.kdl \
         shell/shell.qml shell/assets/wallpaper.jpg shell/assets/FluentSystemIcons-Regular.ttf shell/assets/nixos.svg \
         sddm/Main.qml sddm/metadata.desktop scripts/trial-watchdog.sh scripts/session-check.sh scripts/shell-run.sh scripts/mem.sh scripts/pkg.sh scripts/updater.sh scripts/win11.sh scripts/bt-battery.sh scripts/software-center.sh; do
  [ -s "$SRC/$f" ] || bad "нет файла $f"
done

[ -r /etc/nixos/hardware-configuration.nix ] || bad "нет /etc/nixos/hardware-configuration.nix"
for f in "$SRC"/*.nix; do
  nix-instantiate --parse "$f" >/dev/null 2>"$HOME/.cache/win11-parse.err" || { bad "синтаксис $(basename "$f"): $(head -n 3 "$HOME/.cache/win11-parse.err")"; }
done
for f in "$SRC"/scripts/*.sh; do
  [ -e "$f" ] || continue
  bash -n "$f" 2>/dev/null || bad "синтаксис $(basename "$f")"
done
grep -q '^workspace "min"' "$SRC/niri/config.kdl" || bad "в config.kdl нет рабочего стола min"
grep -q 'win11-session-check' "$SRC/niri/config.kdl" || bad "в config.kdl нет запуска win11-session-check"
fi
[ "$ERRORS" -eq 0 ] || die "Файлы повреждены. Пришлите вывод выше."
ok "файлы на месте, синтаксис верный"

echo "==> 2. Пробная сборка в стороне (текущая система не затрагивается)"
rm -rf "$STAGE"
mkdir -p "$STAGE/win11-shell"
# весь /etc/nixos (ваш конфиг может подключать и другие файлы оттуда), кроме прежних копий оболочки
( cd /etc/nixos && for f in * .[!.]*; do
    case "$f" in win11-shell|win11-shell-kit|*.bak-*|.git|result|'*'|'.[!.]*') continue ;; esac
    cp -r "$f" "$STAGE/" 2>/dev/null || sudo cat "/etc/nixos/$f" > "$STAGE/$f" 2>/dev/null || true
  done )
mkdir -p "$STAGE/win11-shell"
if [ "$GENERIC" -eq 1 ]; then
  if [ -e "$STAGE/configuration-base.nix" ]; then die "В /etc/nixos уже есть configuration-base.nix, но оболочка не подключена. Переименуйте его и запустите установку снова."; fi
  mv "$STAGE/configuration.nix" "$STAGE/configuration-base.nix"
  echo "    первая установка: ваш конфиг будет сохранён как configuration-base.nix и подключён вместе с оболочкой"
fi
cp "$CONF" "$STAGE/configuration.nix" 2>/dev/null || true
if [ "$REBUILD" -eq 1 ]; then
  cp -r "$MOD/." "$STAGE/win11-shell/"
  [ "$FORCE_NORMAL" -eq 1 ] && rm -f "$STAGE/win11-shell/safe-login"
  [ -e "$STAGE/win11-shell/safe-login" ] && MODE=safe
else
  cp -r "$SRC/shell" "$SRC/sddm" "$SRC/scripts" "$SRC/niri-minimize.rs" "$STAGE/win11-shell/"
  # все модули набора разом: список по именам уже однажды отстал от набора
  for f in "$SRC"/*.nix; do
    [ "$(basename "$f")" = example-configuration.nix ] || cp "$f" "$STAGE/win11-shell/"
  done
  # выбор пользователя переживает обновление из нового архива
  for keep in zapret-config zapret-fake zapret-game no-zapret no-printing no-flatpak extra-locales drivers-auto.nix no-zram optimize-nix-store; do
    [ -e "/etc/nixos/win11-shell/$keep" ] && cp "/etc/nixos/win11-shell/$keep" "$STAGE/win11-shell/"
  done

  # ответы на вопросы установки: файл-метка есть - часть выключена (или включён особый режим)
  if [ -n "$ANSWERS" ]; then
    mark() { if [ "$2" = 1 ]; then touch "$STAGE/win11-shell/$1"; else rm -f "$STAGE/win11-shell/$1"; fi; }
    mark no-printing "$([ "$(answer printer)" = none ] && echo 1)"
    mark no-flatpak "$([ "$(answer flatpak)" = 0 ] && echo 1)"
    mark no-zapret "$([ "$(answer zapret)" = 0 ] && echo 1)"
    mark no-zram "$([ "$(answer zram)" = 0 ] && echo 1)"
    mark optimize-nix-store "$([ "$(answer optimize)" = 1 ] && echo 1)"
    if [ "$(answer drivers)" = 1 ]; then
      DRIVER_PLAN="$HOME/.cache/win11-shell/driver-plan.nix"
      if WIN11_DRIVERS_FILE=/dev/null bash "$SRC/scripts/drivers.sh" plan > "$DRIVER_PLAN" && [ -s "$DRIVER_PLAN" ]; then
        echo "Найдена следующая конфигурация драйверов:"
        cat "$DRIVER_PLAN"
        echo "Она может заменить ранее подобранную конфигурацию драйверов."
        printf 'Добавить в пробную сборку? [y/N]: '
        read -r confirm || confirm=""
        if [ "$confirm" = y ] || [ "$confirm" = Y ]; then
          nix-instantiate --parse "$DRIVER_PLAN" >/dev/null || die "Ошибка в предлагаемой конфигурации драйверов."
          cp "$DRIVER_PLAN" "$STAGE/win11-shell/drivers-auto.nix" || die "Не удалось подготовить драйверы."
        fi
      else
        warn "Для этого оборудования не удалось подготовить дополнительные драйверы."
      fi
      rm -f "$DRIVER_PLAN"
    fi
    # язык программ - личная настройка, та же, что в "Параметры" - "Время и язык"
    if [ -n "$(answer lang)" ]; then
      mkdir -p "$HOME/.config/win11-shell"
      answer lang > "$HOME/.config/win11-shell/lang"
      [ -e "$HOME/.config/win11-shell/settings.json" ] || printf '{"lang":"%s"}' "$(answer lang)" > "$HOME/.config/win11-shell/settings.json"
    fi
  fi
fi
if [ "$SAFE" -eq 1 ]; then
  touch "$STAGE/win11-shell/safe-login"
  echo "    безопасный режим: экран входа LightDM"
fi
# Отметка "niri не собрался" ставится автоматически и помнит, для какой версии правки.
# Правка изменилась - пробуем собрать ещё раз, иначе кнопка "Свернуть" не заработала бы никогда.
PATCHSUM="$(cat "$STAGE/win11-shell/niri-patch.nix" "$STAGE/win11-shell/niri-minimize.rs" 2>/dev/null | sha256sum | cut -c1-16)"
if [ "$NOPATCH" -eq 0 ] && [ -e "$STAGE/win11-shell/no-niri-patch" ] \
   && ! grep -q "^manual" "$STAGE/win11-shell/no-niri-patch" \
   && ! grep -q "$PATCHSUM" "$STAGE/win11-shell/no-niri-patch"; then
  rm -f "$STAGE/win11-shell/no-niri-patch"
  echo "    правка niri обновилась - пробую собрать niri с кнопкой \"Свернуть\" ещё раз"
fi
if [ "$NOPATCH" -eq 1 ]; then
  echo "manual" > "$STAGE/win11-shell/no-niri-patch"
elif [ ! -e "$STAGE/win11-shell/no-niri-patch" ]; then
  echo "    niri будет собран из исходников ради кнопки \"Свернуть\". В первый раз это долго"
  echo "    (от 20 минут до часа и больше, компьютер будет сильно загружен). Прерывать не нужно."
fi
if [ "$SYSTEM" -eq 1 ]; then
  echo "    обновляю список пакетов NixOS"
  sudo nix-channel --update || warn "не удалось обновить список пакетов - собираю с текущим"
fi

echo "    печать: общий режим"

BLOG="$HOME/.cache/win11-shell/build.log"
# Ход сборки одной строкой: полоса и проценты вместо сотен строк nix. Весь вывод - в $BLOG.
# Проценты считаются по числу шагов (собрать, скачать), которые nix объявляет заранее;
# долгий шаг (niri из исходников) держит полосу на месте, зато видно его имя.
progress() {
  awk -v log_file="$BLOG" '
    function show(   pct, n, bar, i) {
      pct = total > 0 ? int(done * 100 / total) : 0
      if (pct > 99) pct = 99
      n = int(pct * 30 / 100); bar = ""
      for (i = 0; i < 30; i++) bar = bar (i < n ? "#" : ".")
      printf "\r    [%s] %3d%%  %-44.44s", bar, pct, name
      fflush()
    }
    { print > log_file; fflush(log_file) }
    /^these [0-9]+ derivations will be built/ { total += $2 }
    /^this derivation will be built/ { total += 1 }
    /^these [0-9]+ paths will be fetched/ { total += $2 }
    /^this path will be fetched/ { total += 1 }
    /^(building|copying path) \047\/nix\/store\// {
      name = $0; sub(/^[^\047]*\047\/nix\/store\/[a-z0-9]+-/, "", name); sub(/(\.drv)?\047.*$/, "", name)
      show(); done++
    }
    END { printf "\r%80s\r", "" }'
}
build() {
  if [ "$VERBOSE" -eq 1 ]; then
    nix-build '<nixpkgs/nixos>' -A system -I "nixos-config=$STAGE/configuration.nix" -o "$STAGE/result" 2>&1 | tee "$BLOG"
  else
    nix-build '<nixpkgs/nixos>' -A system -I "nixos-config=$STAGE/configuration.nix" -o "$STAGE/result" 2>&1 | progress
  fi
  return "${PIPESTATUS[0]}"
}
# при сбое - только сама ошибка, а не весь журнал
show_error() {
  [ "$VERBOSE" -eq 1 ] && return 0
  local at
  at="$(grep -n '^error' "$BLOG" | head -n 1 | cut -d: -f1)"
  echo "    Сборка остановилась с ошибкой:"
  if [ -n "$at" ]; then sed -n "${at},\$p" "$BLOG" | grep -v '^ *$' | tail -n 30 | cut -c1-200 | sed 's/^/      /'
  else tail -n 20 "$BLOG" | cut -c1-200 | sed 's/^/      /'; fi
}
# Если не скачивается необязательная программа, собираем без неё.
until build; do
  show_error
  if grep -qE "(builder for|Cannot build) .*-niri-[0-9][^ ]*\\.drv" "$BLOG" && [ ! -e "$STAGE/win11-shell/no-niri-patch" ]; then
    echo "auto $PATCHSUM $(date '+%F %T')" > "$STAGE/win11-shell/no-niri-patch"
    cp "$BLOG" "$HOME/win11-niri-build-error.log" 2>/dev/null
    warn "niri с кнопкой \"Свернуть\" не собрался - ставлю обычный niri."
    warn "Кнопка \"Свернуть\" в заголовках работать НЕ будет. Пришлите файл ~/win11-niri-build-error.log"
  elif grep -qi 'zapret' "$BLOG" && [ ! -e "$STAGE/win11-shell/no-zapret" ]; then
    touch "$STAGE/win11-shell/no-zapret"
    cp "$BLOG" "$HOME/win11-zapret-build-error.log" 2>/dev/null
    warn "zapret (обход замедления YouTube и Discord) не собрался - ставлю без него."
    warn "Пришлите файл ~/win11-zapret-build-error.log; повторить позже: win11-zapret enable"
  elif grep -qi 'discord' "$BLOG" && [ ! -e "$STAGE/win11-shell/no-discord" ]; then
    touch "$STAGE/win11-shell/no-discord"
    warn "Discord не скачался - собираю без него (позже: flatpak install flathub com.discordapp.Discord)"
  elif grep -qi 'hplip' "$BLOG" && [ ! -e "$STAGE/win11-shell/no-hp-plugin" ]; then
    touch "$STAGE/win11-shell/no-hp-plugin"
    warn "модуль HP не скачался - собираю без него"
  else
    cp "$BLOG" "$HOME/win11-build-error.log" 2>/dev/null
    die "Сборка не удалась, система не изменена. Полный журнал: ~/win11-build-error.log"
  fi
done
NEW="$(readlink -f "$STAGE/result")"
ok "система собрана: $NEW"

echo "==> 3. Проверка собранной системы"
R="$STAGE/result"
# параметры из окна "Параметры" лежат рядом с конфигом; если файла ещё нет - берём стандартный
NIRI_SET="$(dirname "$NIRI_CFG")/win11-settings.kdl"
if [ "$REBUILD" -eq 1 ] && [ ! -s "$NIRI_SET" ] && [ -s "$KIT/niri/win11-settings.kdl" ]; then
  cp "$KIT/niri/win11-settings.kdl" "$NIRI_SET"
fi
INLINE=0
if "$R/sw/bin/niri" validate -c "$NIRI_CFG" >"$HOME/.cache/win11-niri.err" 2>&1; then
  ok "конфиг niri принят"
elif grep -q '^include "win11-settings.kdl"' "$NIRI_CFG" && [ -s "$NIRI_SET" ] \
     && { grep -v '^include "win11-settings.kdl"' "$NIRI_CFG"; cat "$NIRI_SET"; } > "$STAGE/config-inline.kdl" \
     && "$R/sw/bin/niri" validate -c "$STAGE/config-inline.kdl" >/dev/null 2>&1; then
  # эта версия niri не умеет подключать файлы: вставляем параметры прямо в конфиг
  INLINE=1
  warn "niri не поддерживает include - параметры клавиатуры и мыши из окна \"Параметры\" применяться не будут"
else
  cat "$HOME/.cache/win11-niri.err" >&2
  bad "niri отверг config.kdl"
fi
for f in sw/bin/niri sw/bin/qs sw/bin/win11-shell-run sw/bin/win11-session-check \
         etc/win11-shell/shell.qml etc/systemd/system/display-manager.service \
         etc/systemd/system/win11-trial.service bin/switch-to-configuration; do
  if [ -e "$R/$f" ]; then ok "$f"; else bad "в сборке нет $f"; fi
done
for f in sw/bin/nmcli sw/bin/wpctl sw/bin/brightnessctl sw/bin/gammastep sw/bin/swayidle \
         sw/bin/win11-minimize sw/bin/jq sw/bin/fd sw/bin/lspci sw/bin/flatpak sw/bin/missioncenter sw/bin/kitty sw/bin/nautilus sw/bin/nm-applet sw/bin/xwayland-satellite \
         sw/bin/win11-shutdown sw/bin/win11-printfix sw/bin/win11-lists sw/bin/win11-pack etc/win11-xkb/X11/xkb/rules/base.lst \
         etc/systemd/system/keyd.service etc/systemd/system/cups.service; do
  [ -e "$R/$f" ] || warn "в сборке нет $f (часть функций не будет работать)"
done

if [ "$SAFE" -eq 0 ] && [ ! -e "$R/sw/share/sddm/themes/win11/Main.qml" ]; then
  warn "тема экрана входа не найдена в сборке"
fi
n_qml="$(ls "$R/etc/win11-shell/"*.qml 2>/dev/null | wc -l)"
n_src="$(ls "$STAGE/win11-shell/shell/"*.qml | wc -l)"
[ "$n_qml" -eq "$n_src" ] || bad "в сборке $n_qml файлов оболочки вместо $n_src"
[ "$ERRORS" -eq 0 ] || die "Проверки не пройдены ($ERRORS). Пришлите вывод выше."
echo "    Проверки пройдены, замечаний: $WARNS."

if [ "$CHECK_ONLY" -eq 1 ]; then
  echo "Режим --check: на этом всё, система не изменена."
  exit 0
fi

if [ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
  echo
  echo "Вы запускаете установку не из графического сеанса."
  echo "Текущая загруженная система будет считаться исправной (к ней идёт возврат при сбое)."
  read -r -p "Она действительно рабочая? [y/N] " ans
  case "$ans" in y|Y|д|Д) ;; *) die "Загрузитесь в рабочую запись GRUB и запустите установку оттуда." ;; esac
fi

echo "==> 4. Копирую файлы в /etc/nixos (прежние сохраняются)"
sudo mkdir -p "$STATE" /var/log/win11-shell
sudo cp /etc/nixos/configuration.nix "/etc/nixos/configuration.nix.bak-$STAMP" || die "Не удалось сохранить конфигурацию."
BACKUP_MOD="(резервной копии не было)"
if sudo test -e /etc/nixos/win11-shell; then
  BACKUP_MOD="/etc/nixos/win11-shell.bak-$STAMP"
  sudo test ! -e "$BACKUP_MOD" || die "Резервная копия уже существует: $BACKUP_MOD"
  sudo cp -a /etc/nixos/win11-shell "$BACKUP_MOD" || die "Не удалось сохранить прежнюю оболочку."
  echo "    прежняя оболочка: $BACKUP_MOD"
fi
sudo rm -rf /etc/nixos/win11-shell || die "Не удалось заменить папку оболочки."
sudo cp -r "$STAGE/win11-shell" /etc/nixos/win11-shell || { echo "Не удалось скопировать оболочку; восстановите $BACKUP_MOD вручную." >&2; exit 1; }
if [ "$REBUILD" -eq 0 ]; then
  if [ "$GENERIC" -eq 1 ]; then
    sudo cp "$STAGE/configuration-base.nix" /etc/nixos/configuration-base.nix
    sudo cp "$STAGE/configuration.nix" /etc/nixos/configuration.nix
    ok "ваш конфиг сохранён: /etc/nixos/configuration-base.nix (и копия configuration.nix.bak-$STAMP)"
  fi
  mkdir -p "$HOME/.config/niri"
  if [ -f "$HOME/.config/niri/config.kdl" ]; then
    cp "$HOME/.config/niri/config.kdl" "$HOME/.config/niri/config.kdl.bak-$STAMP"
  fi
  if [ "$INLINE" -eq 1 ]; then
    cp "$STAGE/config-inline.kdl" "$HOME/.config/niri/config.kdl"
  else
    cp "$SRC/niri/config.kdl" "$HOME/.config/niri/config.kdl"
    # свои параметры не затираем
    [ -s "$HOME/.config/niri/win11-settings.kdl" ] || cp "$SRC/niri/win11-settings.kdl" "$HOME/.config/niri/win11-settings.kdl"
  fi
  # копия комплекта для команды win11-update
  if [ "$SRC" != "$KIT" ]; then
    if sudo test -e "$KIT"; then
      BACKUP_KIT="$KIT.bak-$STAMP"
      sudo test ! -e "$BACKUP_KIT" || { echo "Резервная папка существует: $BACKUP_KIT" >&2; exit 1; }
      sudo cp -a "$KIT" "$BACKUP_KIT" || { echo "Не удалось сохранить прежний комплект." >&2; exit 1; }
      echo "    прежний комплект: $BACKUP_KIT"
    fi
    sudo rm -rf "$KIT" && sudo mkdir -p "$KIT" && sudo cp -r "$SRC/." "$KIT/" || { echo "Не удалось обновить комплект; проверьте резервную копию." >&2; exit 1; }
  fi
fi

# ---------- оборудование: что осталось без драйвера ----------
echo "==> Оборудование"
if [ -x "$R/sw/bin/lspci" ]; then
  NODRV="$("$R/sw/bin/lspci" -k 2>/dev/null | awk '/^[0-9a-f]/ { if (dev != "" && !drv) print dev; dev = $0; drv = 0 } /Kernel driver in use/ { drv = 1 } END { if (dev != "" && !drv) print dev }' | grep -viE 'bridge|SMBus|Signal processing|System peripheral|Memory controller|PIC|Performance|RAM memory|Non-Essential|Serial bus controller \[0c80\]' || true)"
  if [ -n "$NODRV" ]; then
    warn "устройства без драйвера (пришлите этот список, если что-то не работает):"
    echo "$NODRV" | sed 's/^/         /'
  else
    ok "у всех устройств есть драйвер"
  fi
  if "$R/sw/bin/lspci" 2>/dev/null | grep -qiE 'VGA.*NVIDIA|3D.*NVIDIA'; then
    warn "видеокарта NVIDIA: работает открытый драйвер nouveau. Фирменный включается отдельно - напишите, если нужен."
  fi
  if "$R/sw/bin/lspci" -n 2>/dev/null | grep -qE ' 0280: 14e4:'; then
    warn "Wi-Fi Broadcom: некоторым моделям нужен отдельный фирменный драйвер - напишите, если Wi-Fi не виден."
  fi
fi

# ---------- обновление на лету: без перезапуска экрана входа и без перезагрузки ----------
same() { [ "$(readlink -f "$NEW/$1" 2>/dev/null)" = "$(readlink -f "/run/current-system/$1" 2>/dev/null)" ]; }
has_bar() { niri msg --json layers 2>/dev/null | grep -q 'win11-taskbar'; }
restart_shell() {
  local pid
  pid="$(cat "$HOME/.local/state/win11-shell/shell.pid" 2>/dev/null || true)"
  [ -n "$pid" ] && kill -9 "$pid" 2>/dev/null
  sleep 3
}
wait_bar() {
  local i=0
  while [ "$i" -lt 20 ]; do
    if has_bar; then sleep 6; has_bar && return 0; fi
    sleep 2; i=$((i + 1))
  done
  return 1
}

if [ "$NEW" = "$CUR" ]; then
  echo
  echo "Система уже актуальна - пересборка ничего не изменила."
  exit 0
fi

# На лету можно включить всё, кроме нового ядра и его модулей: открытые программы остаются,
# сеанс не закрывается. Новый niri, экран входа и параметры ядра начнут действовать со
# следующего входа или перезагрузки - её тогда проверит сторож (как после смены ядра).
booted_same() { [ "$(readlink -f "$NEW/$1")" = "$(readlink -f "/run/booted-system/$1")" ]; }
LATER=""
same sw/bin/niri || LATER="niri"
same etc/systemd/system/display-manager.service || LATER="$LATER экран входа"
{ same initrd && same kernel-params; } || LATER="$LATER параметры загрузки"

if [ "$FULL" -eq 0 ] && [ -n "${NIRI_SOCKET:-}" ] && has_bar \
   && booted_same kernel && booted_same kernel-modules && same etc/fstab; then
  echo "==> 5. Обновление на лету (открытые программы остаются)"
  sudo nix-env -p "$PROFILE" --set "$NEW" || die "Не удалось записать новую версию."
  sudo "$NEW/bin/switch-to-configuration" switch || warn "включение завершилось с замечаниями"
  restart_shell
  if wait_bar; then
    echo "ok mode=$MODE (обновление на лету)" | sudo tee "$STATE/last-result" >/dev/null
    echo
    if [ -n "$LATER" ]; then
      printf 'PHASE=boot\nOLD=%s\nNEW=%s\nMODE=%s\n' "$CUR" "$NEW" "$MODE" | sudo tee "$STATE/trial" >/dev/null
      echo "Готово. Изменилось то, что нельзя заменить на ходу ($(echo $LATER)):"
      echo "оно начнёт действовать после перезагрузки. Перезагрузиться можно когда удобно."
    else
      echo "Готово: обновлено без перезагрузки."
    fi
    exit 0
  fi
  echo
  echo "Панель задач после обновления не появилась - возвращаю прежнюю версию." >&2
  tail -n 15 "$HOME/.local/state/win11-shell/shell.log" 2>/dev/null >&2
  cp "$HOME/.local/state/win11-shell/shell.log" "$HOME/.local/state/win11-shell/hot-fail-$(date +%Y%m%d-%H%M%S).log" 2>/dev/null
  sudo nix-env -p "$PROFILE" --set "$CUR" && sudo "$CUR/bin/switch-to-configuration" switch
  restart_shell
  echo "failed mode=$MODE phase=hot reason=панель задач не появилась после обновления на лету" | sudo tee "$STATE/last-result" >/dev/null
  echo "Прежняя версия возвращена. Запустите bash doctor.sh и пришлите отчёт." >&2
  exit 1
fi

# Новое ядро или новый набор его модулей (драйвер видеокарты) нельзя включить на ходу:
# работающее ядро остаётся прежним, модулей под него в новой системе нет, и экран входа
# не запускается ("Failed to find module 'nvidia'", "no screens found"). Такую систему
# проверяем только перезагрузкой; при неудаче сторож вернёт нынешнюю.
if ! booted_same kernel || ! booted_same kernel-modules; then
  echo "==> 5. Меняется ядро или драйвер видеокарты - проверка пройдёт после перезагрузки"
  sudo nix-env -p "$PROFILE" --set "$NEW" || die "Не удалось записать новую версию."
  if ! sudo "$NEW/bin/switch-to-configuration" boot; then
    sudo nix-env -p "$PROFILE" --set "$CUR"
    die "Не удалось записать загрузчик. Система не изменена."
  fi
  printf 'PHASE=boot\nOLD=%s\nNEW=%s\nMODE=%s\n' "$CUR" "$NEW" "$MODE" | sudo tee "$STATE/trial" >/dev/null
  echo "pending mode=$MODE (новая система включится после перезагрузки)" | sudo tee "$STATE/last-result" >/dev/null
  cat <<EOF

Новая система записана, но ещё не включена: сейчас ничего не изменилось.
  1. Сохраните работу и перезагрузите компьютер.
  2. Войдите как обычно в течение 10 минут. Появилась панель задач - версия запомнена.
  3. Экран чёрный или входа нет - ничего не делайте: через 10 минут компьютер сам
     перезагрузится в нынешнюю систему. Если не загружается совсем, в меню загрузки
     выберите предыдущую строку (поколение).
EOF
  ans=""
  read -r -p "Перезагрузить сейчас? [y/N] " ans || true
  case "$ans" in y|Y|д|Д) sudo systemctl reboot ;; esac
  exit 0
fi

echo "==> 5. Загрузчик: по умолчанию остаётся текущая рабочая система"
if [ "$(readlink -f "$PROFILE")" != "$CUR" ]; then
  if sudo nix-env -p "$PROFILE" --set "$CUR" && sudo "$CUR/bin/switch-to-configuration" boot; then
    ok "в загрузчике по умолчанию снова текущая система"
  else
    die "Не удалось закрепить текущую систему в загрузчике."
  fi
else
  ok "уже так"
fi

echo "==> 6. Пробное включение новой системы (до подтверждения - только до перезагрузки)"
if sudo "$NEW/bin/switch-to-configuration" test; then
  ok "включена"
else
  warn "включение завершилось с замечаниями; сбойные службы:"
  systemctl --failed --no-pager --no-legend 2>/dev/null | sed 's/^/         /'
fi
for u in NetworkManager keyd $([ -e /etc/nixos/win11-shell/no-printing ] || echo cups); do
  if systemctl is-active --quiet "$u.service"; then ok "служба $u работает"; else warn "служба $u не работает"; fi
done

printf 'PHASE=live\nOLD=%s\nNEW=%s\nMODE=%s\n' "$CUR" "$NEW" "$MODE" | sudo tee "$STATE/trial" >/dev/null
sudo rm -f "$STATE/last-result"

cat <<EOF

==> 7. Проверка рабочего стола
Сейчас экран перезапустится и все открытые программы закроются.
  1. Появится экран входа - войдите как обычно (сеанс niri) в течение 10 минут.
  2. Если появилась панель задач, система сама запомнит новую версию. Делать ничего не нужно.
  3. Если экран чёрный или что-то не так - ничего не делайте: через 10 минут компьютер
     сам перезагрузится в нынешнюю систему. Можно не ждать и нажать Reset.
Первая перезагрузка после успеха проверяется так же (10 минут на вход).
EOF
read -r -p "Нажмите Enter, чтобы начать (Ctrl+C - отменить)... " _
sudo systemctl restart --no-block win11-trial.service
