#!/usr/bin/env bash
# Проверка набора перед публикацией: то же самое запускает GitHub при каждой отправке кода.
#   bash ci/check.sh
# Проверяется синтаксис сценариев, модулей NixOS и QML, служебные метки и сборка установщика.
# Чего нет под рукой (nix, qmllint, shellcheck), то пропускается с пометкой.
set -u
cd "$(dirname "$0")/.."
fails=0
ok()   { printf '  [ok]   %s\n' "$1"; }
skip() { printf '  [--]   %s\n' "$1"; }
bad()  { printf '  [FAIL] %s\n' "$1"; fails=$((fails + 1)); }

echo "== сценарии (bash -n) =="
n=0
for f in *.sh scripts/*.sh ci/*.sh; do
  n=$((n + 1))
  bash -n "$f" 2>/tmp/ci-err || { bad "$f"; sed 's/^/         /' /tmp/ci-err; }
done
ok "проверено файлов: $n"

echo "== сценарии (shellcheck, только ошибки) =="
if command -v shellcheck >/dev/null; then
  if shellcheck -s bash -S error *.sh scripts/*.sh ci/*.sh; then ok "ошибок нет"; else bad "shellcheck нашёл ошибки"; fi
else skip "shellcheck не установлен"; fi

echo "== модули NixOS (разбор) =="
if command -v nix-instantiate >/dev/null; then
  for f in *.nix; do
    nix-instantiate --parse "$f" >/dev/null 2>/tmp/ci-err || { bad "$f"; sed 's/^/         /' /tmp/ci-err | head -n 8; }
  done
  ok "разобрано: $(ls *.nix | wc -l)"
else skip "nix не установлен"; fi

echo "== QML (синтаксис) =="
QMLLINT="$(command -v qmllint || python3 -c 'import PySide6, os; print(os.path.join(os.path.dirname(PySide6.__file__), "qmllint"))' 2>/dev/null)"
if [ -n "$QMLLINT" ] && [ -x "$QMLLINT" ]; then
  # модулей Quickshell здесь нет, поэтому важны только ошибки разбора, а не "не найден тип"
  out="$("$QMLLINT" shell/*.qml sddm/*.qml 2>&1 | grep -B1 -A3 -iE 'syntax error|expected token|unexpected token')"
  if [ -z "$out" ]; then ok "проверено файлов: $(ls shell/*.qml sddm/*.qml | wc -l)"; else bad "ошибки разбора QML"; echo "$out" | sed 's/^/         /'; fi
else skip "qmllint не установлен (pip install pyside6-essentials)"; fi

echo "== номер версии и служебные файлы =="
if grep -qE '^[0-9]{4}\.[0-9]{2}\.[0-9]{2}-[0-9]+$' scripts/version; then ok "версия $(cat scripts/version)"; else bad "scripts/version: ожидается вид 2026.11.14-7"; fi
for m in safe-login no-zapret no-printing no-flatpak drivers-auto.nix zapret-config; do
  [ -e "$m" ] && bad "в набор попала личная метка: $m"
done
ok "личных меток нет"
for f in $(grep -o '\./[a-z0-9-]*\.nix' win11-shell.nix | sort -u); do
  case "$f" in ./drivers-auto.nix) continue ;; esac
  [ -e "$f" ] || bad "win11-shell.nix подключает отсутствующий файл $f"
done
ok "подключаемые модули на месте"

echo "== перевод =="
if python3 ci/i18n.py strict >/tmp/i18n.out 2>&1; then ok "$(tr '\n' ' ' < /tmp/i18n.out)"
else sed 's/^/        /' /tmp/i18n.out; bad "в словарях перевода не хватает строк (ci/i18n.py check)"; fi
cp -r shell /tmp/i18n-shell && python3 ci/i18n.py wrap >/dev/null && diff -rq shell /tmp/i18n-shell >/dev/null \
  && ok "все надписи отданы на перевод" || bad "есть надписи без Tr.t(): запустите python3 ci/i18n.py wrap"
rm -rf /tmp/i18n-shell

echo "== установщик одним файлом =="
out="$(mktemp -d)"
if WIN11_SRC="$PWD" bash scripts/pack.sh "$out/win11-shell-install.sh" >/dev/null 2>&1 \
   && bash -n "$out/win11-shell-install.sh" \
   && HOME="$out/home" bash "$out/win11-shell-install.sh" --extract >/dev/null 2>&1 \
   && [ -s "$out/home/win11-shell/install.sh" ]; then
  ok "собирается и распаковывается ($(du -h "$out/win11-shell-install.sh" | cut -f1))"
  [ -n "${CI_ARTIFACT:-}" ] && cp "$out/win11-shell-install.sh" "$CI_ARTIFACT"
else bad "установщик не собрался или не распаковался"; fi
rm -rf "$out"

echo
if [ "$fails" -eq 0 ]; then echo "Все проверки пройдены."; else echo "Не пройдено проверок: $fails"; fi
exit "$fails"
