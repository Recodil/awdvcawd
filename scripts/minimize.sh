# win11-minimize <номер окна>   свернуть окно (вызывают niri - кнопка в заголовке - и панель задач)
# win11-minimize                свернуть активное окно
# win11-minimize --restore <номер окна> [стол]   вернуть свёрнутое окно
# win11-minimize --check        почему не работает кнопка "Свернуть"
export PATH="$PATH:/run/current-system/sw/bin"
LOG="${XDG_STATE_HOME:-$HOME/.local/state}/win11-shell/minimize.log"
mkdir -p "${LOG%/*}" 2>/dev/null

if [ "${1:-}" = "--check" ]; then
  echo "== Кнопка \"Свернуть\" =="
  bin="$(readlink -f "$(command -v niri)" 2>/dev/null)"
  echo "niri: ${bin:-не найден}  ($(niri --version 2>/dev/null))"
  if [ -e /etc/nixos/win11-shell/no-niri-patch ]; then
    echo "[!!] правка niri отключена (файл /etc/nixos/win11-shell/no-niri-patch): $(cat /etc/nixos/win11-shell/no-niri-patch 2>/dev/null)"
    echo "     включить: sudo rm /etc/nixos/win11-shell/no-niri-patch && win11-update --full"
  fi
  if [ -n "$bin" ] && grep -qa 'win11-minimize' "$bin"; then
    echo "[ok] установленный niri собран с правкой"
  else
    echo "[!!] установленный niri - обычный, без правки: кнопка в заголовке работать не может"
  fi
  pid="$(pgrep -x niri | head -n 1)"
  if [ -n "$pid" ]; then
    run="$(readlink -f "/proc/$pid/exe" 2>/dev/null)"
    if [ "$run" = "$bin" ]; then echo "[ok] запущен именно он"
    else echo "[!!] сейчас запущен старый niri ($run) - перезагрузите компьютер"; fi
  fi
  echo "кнопки в заголовках (dconf): $(dconf read /org/gnome/desktop/wm/preferences/button-layout 2>/dev/null)"
  for v in 3.0 4.0; do echo "gtk-$v: $(grep -h '^gtk-decoration-layout' "$HOME/.config/gtk-$v/settings.ini" 2>/dev/null)"; done
  if niri msg --json workspaces 2>/dev/null | grep -q '"name":"min"'; then echo "[ok] скрытый стол min есть"
  else echo "[!!] в конфиге niri нет рабочего стола min"; fi
  echo "-- последние нажатия ($LOG) --"
  tail -n 8 "$LOG" 2>/dev/null || echo "нажатий ещё не было: niri ни разу не получил запрос от окна"
  exit 0
fi

# ---- плавное сворачивание ----
# niri умеет плавно двигать плавающие окна. Поэтому "свернуть" = окно уезжает вниз, к панели задач,
# и только потом переносится на скрытый стол; "развернуть" = возвращается на стол и поднимается
# на прежнее место. Выключается в "Параметрах" → "Окна и анимации". Если что-то из этого
# не поддерживается (старый niri, нет jq, окно не плавающее) - окно сворачивается сразу, как раньше.
RUN="${XDG_RUNTIME_DIR:-/tmp}/win11-shell/min"
mkdir -p "$RUN" 2>/dev/null
anim_on() {
  command -v jq >/dev/null 2>&1 || return 1
  grep -q '"minAnim": *false' "$HOME/.config/win11-shell/settings.json" 2>/dev/null && return 1
  return 0
}
# положение плавающего окна на экране: "x y высота"; пусто - узнать нельзя
win_pos() {
  niri msg --json windows 2>/dev/null | jq -r --argjson id "$1" '
    .[] | select(.id == $id) | select(.is_floating == true)
    | select(.layout.tile_pos_in_workspace_view != null)
    | "\(.layout.tile_pos_in_workspace_view[0] | round) \(.layout.tile_pos_in_workspace_view[1] | round) \(.layout.window_size[1] // 0 | round)"' 2>/dev/null
}
screen_h() {
  niri msg --json focused-output 2>/dev/null | jq -r '.logical.height // 1080' 2>/dev/null || echo 1080
}
signed() { if [ "$1" -ge 0 ]; then echo "+$1"; else echo "$1"; fi; }

if [ "${1:-}" = "--restore" ]; then
  id="${2:-}"; ws="${3:-}"
  [ -n "$id" ] || exit 1
  if [ -z "$ws" ]; then
    ws="$(niri msg --json workspaces 2>/dev/null | jq -r '[.[] | select(.name != "min")] | (map(select(.is_focused)) + .)[0].idx' 2>/dev/null)"
    [ -n "$ws" ] && [ "$ws" != "null" ] || ws=1
  fi
  niri msg action move-window-to-workspace --window-id "$id" --focus false "$ws" >/dev/null 2>&1
  # сразу на передний план; плавный подъём на прежнее место идёт уже у активного окна
  niri msg action focus-window --id "$id" >/dev/null 2>&1
  saved="$(cat "$RUN/$id" 2>/dev/null)"; rm -f "$RUN/$id"
  if [ -n "$saved" ] && anim_on; then
    sleep 0.04
    now="$(win_pos "$id")"
    if [ -n "$now" ]; then
      set -- $saved; sx="$1"; sy="$2"
      set -- $now;   nx="$1"; ny="$2"
      dx=$((sx - nx)); dy=$((sy - ny))
      if [ "$dx" -ne 0 ] || [ "$dy" -ne 0 ]; then
        niri msg action move-floating-window --id "$id" -x="$(signed "$dx")" -y="$(signed "$dy")" >/dev/null 2>&1
      fi
    fi
  fi
  exit 0
fi

id="${1:-}"
if [ -z "$id" ]; then
  id="$(niri msg --json focused-window 2>/dev/null | sed -n 's/.*"id":\([0-9]*\).*/\1/p' | head -n 1)"
fi
[ -n "$id" ] || { echo "$(date '+%F %T') окно не указано" >> "$LOG"; exit 1; }
case "$id" in *[!0-9]*) echo "$(date '+%F %T') неверный номер окна: $id" >> "$LOG"; exit 1 ;; esac

# Окно, которое было позади сворачиваемого (последнее активное на том же столе), сразу
# выходит на передний план - не дожидаясь, пока свёрнутое уедет вниз.
behind="$(niri msg --json windows 2>/dev/null | jq -r --argjson id "$id" '
  (.[] | select(.id == $id) | .workspace_id) as $ws
  | [.[] | select(.id != $id and .workspace_id == $ws)]
  | sort_by((.focus_timestamp.secs // 0) + (.focus_timestamp.nanos // 0) / 1e9) | last | .id // empty' 2>/dev/null)"
[ -n "$behind" ] && niri msg action focus-window --id "$behind" >/dev/null 2>&1

rm -f "$RUN/$id"
if anim_on; then
  pos="$(win_pos "$id")"
  if [ -n "$pos" ]; then
    set -- $pos; py="$2"
    drop=$(( $(screen_h) - py ))
    if [ "$drop" -gt 0 ] && niri msg action move-floating-window --id "$id" -x="+0" -y="+$drop" >/dev/null 2>&1; then
      echo "$pos" > "$RUN/$id"
      sleep 0.22
    fi
  fi
fi
if out="$(niri msg action move-window-to-workspace --window-id "$id" --focus false min 2>&1)"; then
  echo "$(date '+%F %T') окно $id свёрнуто" >> "$LOG"
else
  echo "$(date '+%F %T') окно $id: ошибка: $out" >> "$LOG"
  # не оставляем окно внизу экрана, если свернуть не вышло
  [ -e "$RUN/$id" ] && exec "$0" --restore "$id"
  exit 1
fi
# журнал не растёт
[ "$(wc -l < "$LOG" 2>/dev/null || echo 0)" -gt 200 ] && { tail -n 100 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"; }
exit 0
