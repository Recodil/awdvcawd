# Вопросы первой установки. Вызывается из install.sh; ответы пишет в файл $1 строками
# "имя=значение". Сам ничего в системе не меняет: что делать с ответами, решает установщик.
#   lang=ru_RU.UTF-8   язык программ (пусто - как в системе)
#   printer=none|generic
#   flatpak=1|0   zapret=1|0   minimize=1|0   optimize=1|0   zram=1|0   drivers=1|0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$1"
: > "$OUT"

RU=1
say() { if [ "$RU" -eq 1 ]; then printf '%s\n' "$1"; else printf '%s\n' "$2"; fi; }

# pick ЗАГОЛОВОК_RU ЗАГОЛОВОК_EN ПО_УМОЛЧАНИЮ "ключ|рус|eng"...  -> ключ в REPLY
pick() {
  local ru="$1" en="$2" def="$3" i=1 n ans item
  shift 3
  echo; say "$ru" "$en"
  for item in "$@"; do
    IFS='|' read -r _ a b <<EOF2
$item
EOF2
    printf '  %d) %s%s\n' "$i" "$([ "$RU" -eq 1 ] && echo "$a" || echo "$b")" "$([ "$i" -eq "$def" ] && echo "  *")"
    i=$((i + 1))
  done
  n=$#
  while :; do
    printf '%s [%d]: ' "$(say "Номер" "Number")" "$def"
    read -r ans || ans=""
    [ -z "$ans" ] && ans="$def"
    case "$ans" in *[!0-9]*) continue ;; esac
    [ "$ans" -ge 1 ] && [ "$ans" -le "$n" ] && break
  done
  eval "item=\${$ans}"
  REPLY="${item%%|*}"
}

echo
echo "Язык / Language"
LANGS="ru_RU|Русский
en_US|English
uk_UA|Українська
be_BY|Беларуская
kk_KZ|Қазақша
de_DE|Deutsch
fr_FR|Français
es_ES|Español
it_IT|Italiano
pt_BR|Português (Brasil)
pl_PL|Polski
tr_TR|Türkçe
zh_CN|中文
ja_JP|日本語"
i=1
echo "$LANGS" | while IFS='|' read -r _ name; do printf '  %2d) %s\n' "$i" "$name"; i=$((i + 1)); done
echo "   0) как в системе / keep the system language"
while :; do
  printf 'Номер / Number [1]: '
  read -r ans || ans=""
  [ -z "$ans" ] && ans=1
  case "$ans" in *[!0-9]*) continue ;; esac
  [ "$ans" -le 14 ] && break
done
if [ "$ans" -eq 0 ]; then
  code=""
  case "${LANG:-}" in ru*|uk*|be*|kk*) RU=1 ;; *) RU=0 ;; esac
else
  code="$(echo "$LANGS" | sed -n "${ans}p" | cut -d'|' -f1)"
  case "$code" in ru_RU|uk_UA|be_BY|kk_KZ) RU=1 ;; *) RU=0 ;; esac
fi
echo "lang=${code:+$code.UTF-8}" >> "$OUT"

pick "Принтер" "Printer" 2 \
  "none|не нужен|not needed" \
  "generic|любой принтер (служба печати и распространённые драйверы)|any printer (print service and common drivers)"
echo "printer=$REPLY" >> "$OUT"

pick "Откуда ставить программы" "Where to install apps from" 1 \
  "1|NixOS и Flathub|NixOS and Flathub" \
  "0|только NixOS|NixOS only"
echo "flatpak=$REPLY" >> "$OUT"

pick "Необязательный сетевой компонент zapret" "Optional network component zapret" 2 \
  "1|включить|enable" \
  "0|не нужен|not needed"
echo "zapret=$REPLY" >> "$OUT"

pick "Кнопка \"Свернуть\" у окон. Для неё niri собирается из исходников: один раз, от 20 минут до часа" \
     "Window \"Minimize\" button. It needs niri built from source: once, 20 to 60 minutes" 2 \
  "1|нужна|yes" \
  "0|обойдусь, ставить быстрее|no, install faster"
echo "minimize=$REPLY" >> "$OUT"

pick "Оптимизация Nix-хранилища" "Nix store optimization" 2 \
  "1|еженедельно удалять дубликаты в Nix store (может нагружать диск; данные пользователя не удаляются)|deduplicate the Nix store weekly (may use disk I/O; user files are not removed)" \
  "0|не менять настройки накопителя|leave storage settings unchanged"
echo "optimize=$REPLY" >> "$OUT"

pick "Сжатая подкачка zram" "Compressed zram swap" 1 \
  "1|разрешить zram по умолчанию (использует ОЗУ и процессор)|allow zram by default (uses memory and CPU)" \
  "0|не включать zram автоматически|do not enable zram automatically"
echo "zram=$REPLY" >> "$OUT"

echo
say "Проверяю оборудование и известные драйверы. Отчёт показывается локально." \
    "Scanning hardware and known drivers. The report is shown locally."
if ! WIN11_DRIVERS_FILE=/dev/null bash "$SCRIPT_DIR/drivers.sh" search; then
  say "Не удалось получить полный отчёт; драйверы можно проверить позже в Центре обновления." \
      "Hardware scan failed; drivers can be reviewed later in Update Center."
fi
pick "Добавить рекомендованные драйверы в пробную сборку? Возможны закрытые драйверы и несовместимость." \
     "Add suggested drivers to the test build? They may include proprietary or incompatible drivers." 2 \
  "1|да, показать конфигурацию и добавить после подтверждения|yes, show configuration and confirm before adding" \
  "0|нет, проверить позже|no, review later"
echo "drivers=$REPLY" >> "$OUT"
