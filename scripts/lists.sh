# win11-lists - полные списки для окна "Параметры": часовые пояса, раскладки клавиатуры, языки.
#   win11-lists zones     Europe/Moscow<TAB>+03:00
#   win11-lists layouts   ru<TAB>Russian   и варианты:  ru(phonetic)<TAB>Russian (phonetic)
#   win11-lists locales   ru_RU.UTF-8
#   win11-lists all       всё сразу, разделы начинаются строками @zones, @layouts, @locales
export PATH="$PATH:/run/current-system/sw/bin"

zones() {
  local list z
  list="$(timedatectl list-timezones 2>/dev/null)"
  if [ -z "$list" ]; then
    for d in /etc/zoneinfo /usr/share/zoneinfo; do
      [ -d "$d" ] && { list="$(cd "$d" && find -L . -type f 2>/dev/null | sed 's|^\./||' | grep -E '^(Africa|America|Antarctica|Asia|Atlantic|Australia|Europe|Indian|Pacific)/|^UTC$' | sort)"; break; }
    done
  fi
  printf '%s\n' "$list" | while read -r z; do
    [ -n "$z" ] && printf '%s\t%s\n' "$z" "$(TZ="$z" date +%:z 2>/dev/null)"
  done
}

layouts() {
  local f=""
  for c in /etc/win11-xkb/X11/xkb/rules/base.lst /run/current-system/sw/share/X11/xkb/rules/base.lst \
           /usr/share/X11/xkb/rules/base.lst "${XKB_CONFIG_ROOT:-/nonexistent}/rules/base.lst"; do
    [ -r "$c" ] && { f="$c"; break; }
  done
  [ -n "$f" ] || return 0
  awk '
    /^! /            { sec = $2; next }
    sec == "layout" && NF >= 2 {
      code = $1; $1 = ""; sub(/^ +/, ""); print code "\t" $0
    }
    sec == "variant" && NF >= 3 {
      var = $1; lay = $2; sub(/:$/, "", lay); $1 = ""; $2 = ""; sub(/^ +/, ""); print lay "(" var ")\t" $0
    }' "$f" | grep -v '^custom'
}

locales() {
  locale -a 2>/dev/null | grep -iE '\.utf-?8$' | sed -E 's/\.utf-?8$/.UTF-8/I' | sort -u
}

case "${1:-all}" in
  zones) zones ;;
  layouts) layouts ;;
  locales) locales ;;
  all) echo "@zones"; zones; echo "@layouts"; layouts; echo "@locales"; locales ;;
  *) sed -n '1,5p' "$0" | sed 's/^# \{0,1\}//' ;;
esac
