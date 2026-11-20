# win11-printfix - печать на любом принтере: состояние и починка без знания команд CUPS.
#   win11-printfix            состояние принтеров и очереди
#   win11-printfix fix        перезапустить службу печати, снять паузы, убрать зависшие задания
#   win11-printfix clear      очистить очередь печати
#   win11-printfix test       напечатать пробную страницу на принтере по умолчанию
#   win11-printfix add        открыть окно добавления принтера
export PATH="$PATH:/run/current-system/sw/bin"
have() { command -v "$1" >/dev/null 2>&1; }
have lpstat || { echo "Служба печати (CUPS) не установлена."; exit 1; }
SUDO=""; [ "$(id -u)" -eq 0 ] || SUDO="sudo"

status() {
  if systemctl is-active --quiet cups.service 2>/dev/null || systemctl is-active --quiet cups.socket 2>/dev/null; then echo "[ok] служба печати работает"
  else echo "[!!] служба печати не запущена - нажмите \"Починить печать\""; fi
  printers="$(lpstat -e 2>/dev/null)"
  if [ -z "$printers" ]; then
    echo "[!!] принтеров нет. Подключите принтер и нажмите \"Добавить принтер\"."
    echo "     Сетевые принтеры с AirPrint/IPP обычно находятся сами через минуту."
    return 1
  fi
  def="$(lpstat -d 2>/dev/null | sed 's/.*: //')"
  echo "Принтер по умолчанию: ${def:-не выбран}"
  echo
  LC_ALL=C lpstat -p 2>/dev/null | while read -r _ name rest; do
    case "$rest" in
      *disabled*) echo "[!!] $name: остановлен (пауза)" ;;
      *idle*)     echo "[ok] $name: готов" ;;
      *printing*) echo "[..] $name: печатает" ;;
      *)          echo "[??] $name: $rest" ;;
    esac
  done
  jobs="$(lpstat -o 2>/dev/null | wc -l)"
  echo
  echo "Заданий в очереди: $jobs"
  return 0
}

case "${1:-status}" in
  status) status ;;
  fix)
    echo "==> перезапускаю службу печати"
    $SUDO systemctl restart cups.service || echo "[!!] не удалось перезапустить cups"
    sleep 2
    for p in $(lpstat -e 2>/dev/null); do
      echo "==> $p: снимаю паузу, разрешаю приём заданий"
      $SUDO cupsenable "$p" 2>/dev/null; $SUDO cupsaccept "$p" 2>/dev/null
    done
    if [ -z "$(lpstat -d 2>/dev/null | grep ': ')" ]; then
      first="$(lpstat -e 2>/dev/null | head -n 1)"
      [ -n "$first" ] && { echo "==> принтер по умолчанию: $first"; $SUDO lpadmin -d "$first" 2>/dev/null || lpoptions -d "$first" >/dev/null; }
    fi
    echo; status ;;
  clear)
    $SUDO cancel -a -x 2>/dev/null || cancel -a 2>/dev/null
    echo "Очередь печати очищена." ;;
  test)
    def="$(lpstat -d 2>/dev/null | sed -n 's/.*: //p')"
    [ -n "$def" ] || def="$(lpstat -e 2>/dev/null | head -n 1)"
    [ -n "$def" ] || { echo "Принтеров нет."; exit 1; }
    printf 'Пробная страница\n\nПринтер: %s\nКомпьютер: %s\nВремя: %s\n\nЕсли вы это читаете, печать работает.\n' "$def" "$(hostname)" "$(date '+%d.%m.%Y %H:%M')" \
      | lp -d "$def" -t "Пробная страница" && echo "Пробная страница отправлена на \"$def\"." ;;
  add)
    if have system-config-printer; then setsid -f system-config-printer >/dev/null 2>&1
    else xdg-open http://localhost:631/admin >/dev/null 2>&1; fi ;;
  *) sed -n '1,7p' "$0" | sed 's/^# \{0,1\}//' ;;
esac
