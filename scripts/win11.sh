# win11 - все команды оболочки в одном месте. Работает из любого терминала и из "Выполнить" (Win+R).
#   win11                 этот список
#   win11 <команда> ...   то же, что win11-<команда> ...
export PATH="$PATH:/run/current-system/sw/bin"
KIT=/etc/nixos/win11-shell-kit
ipc="start search run hub dnd quick calendar settings updates taskmgr lock logout poweroff reboot dark overview desktopNext desktopPrev desktopNew minimize restoreAll showDesktop"

help() {
  cat <<'EOF'
Команды оболочки (каждая работает и как "win11 имя", и как "win11-имя"):

  Обновление и установка
    win11 update [архив.zip]     поставить новую версию или пересобрать систему
    win11 update --system        то же + обновить все программы NixOS
    win11 updater run [архив]    то же в отдельном окне
    win11 install [--safe…]      установщик из комплекта (обычно не нужен)

  Центр обновления Windows
    win11 updates                открыть окно центра обновления
    win11 updates check          что можно обновить (текстом)
    win11 updates apply all      обновить всё: NixOS, оболочку, программы, драйверы
    win11 drivers                какое оборудование найдено и какие драйверы подобраны
    win11 drivers apply          установить подобранные драйверы
    win11 sound                  что система знает о звуке;  win11 sound fix - починить

  Проверка и починка
    win11 doctor                 отчёт о системе в ~/win11-report.txt
    win11 mem                    на что уходит память (лучше через sudo)
    win11 minimize --check       почему не работает кнопка "Свернуть"
    win11 session-check          проверка сеанса (запускается сама при входе)

  Интернет
    win11 zapret                 состояние обхода замедления YouTube и Discord
    win11 zapret check | test | list | set ИМЯ | on | off | enable | disable
    win11 zapret voice           если звонок Discord висит на "RTC connecting"
    win11 zapret fake [ИМЯ]      подставной пакет для звонков Discord
    win11 zapret game РЕЖИМ      игровой фильтр: off, udp, tcp, all

  Программы
    win11 pkg search ТЕКСТ       поиск программ
    win11 pkg install nix|flatpak ИМЯ     установить
    win11 pkg remove  nix|flatpak ИМЯ     удалить

  Печать
    win11 printfix [fix|clear|test|add]   состояние и починка печати (любой принтер)

  Завершение работы (параметры как в Windows)
    win11 shutdown /s | /r | /l | /h | /a  [/t сек] [/c "текст"]
    то же самое: shutdown /r /t 500

  Поделиться сборкой
    win11 pack [файл]            собрать установщик одним файлом

  Окна оболочки
    win11 hub                    центр управления: всё то же самое кнопками
    win11 start | search | run | settings | quick | calendar | overview
    win11 lock | logout | poweroff | reboot | dark | dnd
    win11 desktopNext | desktopPrev | desktopNew | minimize | restoreAll | showDesktop
EOF
}

cmd="${1:-}"
[ -n "$cmd" ] || { help; exit 0; }
shift
case "$cmd" in
  help|-h|--help) help ;;
  store)
    if command -v software-center >/dev/null 2>&1; then
      exec software-center "$@"
    elif command -v nix-software-center >/dev/null 2>&1; then
      exec nix-software-center "$@"
    elif [ -x "$HOME/.local/bin/software-center" ]; then
      exec "$HOME/.local/bin/software-center" "$@"
    else
      exec qs -p /etc/win11-shell ipc call shell settings apps
    fi ;;
  bt-battery) exec win11-bt-battery "$@" ;;
  recovery) exec win11-recovery "$@" ;;
  minimize)
    # с параметрами - сценарий сворачивания, без них - свернуть активное окно через оболочку
    if [ "$#" -gt 0 ]; then exec win11-minimize "$@"; else exec qs -p /etc/win11-shell ipc call shell minimize; fi ;;
  updates)
    # с параметрами - сценарий центра обновления, без них - его окно
    if [ "$#" -gt 0 ]; then exec win11-updates "$@"; else exec qs -p /etc/win11-shell ipc call shell updates; fi ;;
  *)
    for name in $ipc; do
      [ "$cmd" = "$name" ] && exec qs -p /etc/win11-shell ipc call shell "$cmd"
    done
    if command -v "win11-$cmd" >/dev/null 2>&1; then exec "win11-$cmd" "$@"; fi
    echo "Нет команды \"$cmd\". Список: win11" >&2; exit 1 ;;
esac
