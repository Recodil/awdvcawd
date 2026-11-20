# win11-pack - собрать всю сборку в ОДИН файл-установщик, чтобы поделиться ею.
#   win11-pack [куда/win11-shell-install.sh]
# Получателю достаточно выполнить:  bash win11-shell-install.sh
# Внутри - все файлы оболочки (стили, обои, значки, сценарии, модули NixOS). Личные настройки,
# пароли и ваш configuration.nix в файл не попадают.
export PATH="$PATH:/run/current-system/sw/bin"
set -euo pipefail
SRC="${WIN11_SRC:-/etc/nixos/win11-shell-kit}"
OUT="${1:-$HOME/win11-shell-install.sh}"
[ -s "$SRC/install.sh" ] || { echo "Нет комплекта в $SRC" >&2; exit 1; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir "$TMP/win11-shell"
if git -C "$SRC" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$SRC" ls-files -z | while IFS= read -r -d '' f; do
    case "$f" in */__pycache__/*|*.pyc|*.pyo) continue ;; esac
    [ -f "$SRC/$f" ] || { echo "Отсутствует отслеживаемый файл: $f" >&2; exit 1; }
    printf '%s\0' "$f"
  done | tar -C "$SRC" --null -T - -cf - | tar -C "$TMP/win11-shell" -xf -
else
  echo "Для безопасной сборки требуется Git-репозиторий с отслеживаемыми файлами." >&2
  exit 1
fi
# личное и лишнее не раздаём
( cd "$TMP/win11-shell" && rm -rf preview safe-login no-niri-patch no-zapret no-discord no-hp-plugin zapret-config zapret-fake zapret-game extra-locales drivers-auto.nix ./*.bak-* 2>/dev/null || true )
VER="$(date '+%Y-%m-%d %H:%M')"
cat > "$OUT" <<'HEAD'
#!/usr/bin/env bash
# Оболочка в стиле Windows 11 для NixOS - установщик одним файлом.
#   bash win11-shell-install.sh              установить (без sudo: пароль спросит сам)
#   bash win11-shell-install.sh --check      только проверить и собрать, систему не менять
#   bash win11-shell-install.sh --safe       запасной экран входа (если обычный не заработал)
#   bash win11-shell-install.sh --extract    только распаковать файлы в ~/win11-shell
# Что делает: распаковывает файлы в ~/win11-shell и запускает их install.sh. Тот подключает оболочку
# к вашему /etc/nixos/configuration.nix (сам файл сохраняется), собирает систему в стороне, проверяет
# её и только потом включает; если рабочий стол не появится - сам возвращает прежнюю систему.
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Запустите без sudo: bash $0" >&2; exit 1; }
[ -f "$0" ] || { echo "Сохраните установщик в файл и запустите: bash win11-shell-install.sh" >&2; exit 1; }
DIR="${WIN11_DIR:-$HOME/win11-shell}"
LINE="$(awk '/^__WIN11_PAYLOAD__$/ { print NR + 1; exit }' "$0")"
[ -n "$LINE" ] || { echo "Файл установщика повреждён (нет данных)." >&2; exit 1; }
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
echo "==> Распаковка в $DIR"
if ! tail -n +"$LINE" "$0" | base64 -d 2>/dev/null | tar -xz -C "$TMP" 2>/dev/null || [ ! -s "$TMP/win11-shell/install.sh" ]; then
  echo "Файл установщика повреждён или скачан не полностью - скачайте его заново." >&2
  exit 1
fi
mkdir -p "$(dirname "$DIR")"
if [ -e "$DIR" ]; then
  backup="$DIR.old.$(date +%Y%m%d-%H%M%S)"
  [ ! -e "$backup" ] || { echo "Резервная папка уже существует: $backup" >&2; exit 1; }
  mv "$DIR" "$backup"
  echo "Прежняя папка сохранена: $backup"
fi
mv "$TMP/win11-shell" "$DIR"
if [ "${1:-}" = "--extract" ]; then echo "Готово: $DIR"; exit 0; fi
rm -rf "$TMP"; trap - EXIT
exec bash "$DIR/install.sh" "$@"
exit 1
HEAD
sed -i "2s|\$| Версия от $VER.|" "$OUT"
echo "__WIN11_PAYLOAD__" >> "$OUT"
tar -cz -C "$TMP" win11-shell | base64 -w 76 >> "$OUT"
chmod +x "$OUT" 2>/dev/null || true
echo "Готово: $OUT ($(du -h "$OUT" | cut -f1))"
echo "Передайте этот файл; на другом компьютере с NixOS: bash $(basename "$OUT")"
