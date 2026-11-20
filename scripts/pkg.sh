# win11-pkg - установка и удаление программ (для окна "Параметры" - "Приложения").
#   win11-pkg list                     каталог популярных программ и всё установленное
#   win11-pkg search ТЕКСТ             поиск по всем источникам
#   win11-pkg install ИСТОЧНИК ИМЯ     ИСТОЧНИК: nix, nix:имя, flatpak, flatpak:имя, appimage (ИМЯ - путь к файлу)
#   win11-pkg remove  ИСТОЧНИК ИМЯ
#   win11-pkg sources                  список источников: вид<TAB>имя<TAB>адрес<TAB>можно ли удалить
#   win11-pkg source add nix|flatpak ИМЯ АДРЕС   |   source remove nix|flatpak ИМЯ
#   win11-pkg doctor                   почему не виден Flathub
# Программы ставятся в профиль пользователя: пароль не нужен, система не пересобирается.
# Строки list и search: состояние<TAB>источник<TAB>имя<TAB>название<TAB>описание
export PATH="$PATH:/run/current-system/sw/bin"
export LC_ALL=C.UTF-8
T="$(printf '\t')"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/win11-shell"
REC="$STATE/pkgs-nix"            # установлено из NixOS: имя<TAB>имя пакета в профиле<TAB>источник
NIX_SOURCES="$STATE/sources-nix" # свои источники пакетов Nix: имя<TAB>адрес
APPIMAGES="$HOME/.local/share/win11-shell/appimages"
FLATHUB=https://dl.flathub.org/repo/flathub.flatpakrepo
mkdir -p "$STATE"; touch "$REC" "$NIX_SOURCES"

row() { printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5"; }
lower() { sed 's/.*/\L&/'; }
fail() { echo "ERR $1"; exit 1; }
# выполнить команду, показывая вместо её вывода проценты: строки "PCT число пояснение".
# Понимает сообщения nix (сколько пакетов скачать и собрать) и flatpak (проценты по каждой части).
# Сам вывод остаётся в журнале: его хвост показывается при ошибке.
PKG_LOG="${XDG_CACHE_HOME:-$HOME/.cache}/win11-shell/pkg.log"
meter() {
  awk -v log_file="$PKG_LOG" '
    function show(p, name) {
      if (p > 99) p = 99
      if (p < last) p = last
      last = p
      printf "PCT %d %s\n", p, name; fflush()
    }
    { print > log_file; fflush(log_file) }
    /^these [0-9]+ (derivations will be built|paths will be fetched)/ { total += $2 }
    /^this (derivation will be built|path will be fetched)/ { total += 1 }
    /^(building|copying path) \047\/nix\/store\// {
      name = $0; sub(/^[^\047]*\047\/nix\/store\/[a-z0-9]+-/, "", name); sub(/(\.drv)?\047.*$/, "", name)
      show(total > 0 ? int(done * 100 / total) : 0, name); done++
    }
    match($0, /[0-9]+%/) {
      p = substr($0, RSTART, RLENGTH - 1) + 0
      part = 1; parts = 1
      if (match($0, /[0-9]+\/[0-9]+/)) { split(substr($0, RSTART, RLENGTH), f, "/"); part = f[1] + 0; parts = f[2] + 0 }
      if (parts < 1) parts = 1
      show(int(((part - 1) * 100 + p) / parts), "")
    }'
}
stream() {
  mkdir -p "${PKG_LOG%/*}"
  "$@" 2>&1 | tr '\r' '\n' | meter
  local rc="${PIPESTATUS[0]}"
  [ "$rc" -eq 0 ] || tail -n 3 "$PKG_LOG" | cut -c1-200
  return "$rc"
}

# ---- каталог: имя в NixOS | название | описание ----
catalog() { cat <<'EOF'
firefox|Firefox|Браузер
ungoogled-chromium|Chromium|Браузер без служб Google
google-chrome|Google Chrome|Браузер
discord|Discord|Голосовой и текстовый чат Дискорд
telegram-desktop|Telegram|Мессенджер Телеграм
vlc|VLC|Проигрыватель видео и музыки
mpv|mpv|Лёгкий проигрыватель видео
obs-studio|OBS Studio|Запись экрана и трансляции
steam|Steam|Магазин и библиотека игр
lutris|Lutris|Запуск игр Windows
libreoffice|LibreOffice|Документы, таблицы, презентации
onlyoffice-desktopeditors|OnlyOffice|Офисный пакет, похожий на MS Office
gimp|GIMP|Редактор изображений
krita|Krita|Рисование
inkscape|Inkscape|Векторная графика
kdePackages.kdenlive|Kdenlive|Видеомонтаж
audacity|Audacity|Редактор звука
qbittorrent|qBittorrent|Торрент-клиент
vscode|Visual Studio Code|Редактор кода
vscodium|VSCodium|Редактор кода без телеметрии
thunderbird|Thunderbird|Почта
keepassxc|KeePassXC|Менеджер паролей
obsidian|Obsidian|Заметки
spotify|Spotify|Музыка
zoom-us|Zoom|Видеозвонки
anydesk|AnyDesk|Удалённый рабочий стол
bottles|Bottles|Запуск программ Windows
gparted|GParted|Разделы дисков
file-roller|Архиватор|Архивы zip, rar, 7z
gnome-calculator|Калькулятор|Калькулятор
gnome-text-editor|Текстовый редактор|Блокнот
loupe|Просмотр изображений|Фотографии и картинки
evince|Просмотр документов|PDF
btop|btop|Монитор ресурсов в терминале
fastfetch|fastfetch|Сведения о системе в терминале
EOF
}

# популярное на Flathub: имя | название | описание
flat_catalog() { cat <<'EOF'
com.discordapp.Discord|Discord|Голосовой и текстовый чат
org.telegram.desktop|Telegram|Мессенджер
com.spotify.Client|Spotify|Музыка
com.valvesoftware.Steam|Steam|Магазин и библиотека игр
com.heroicgameslauncher.hgl|Heroic|Игры Epic Games и GOG
org.prismlauncher.PrismLauncher|Prism Launcher|Minecraft
com.usebottles.bottles|Bottles|Запуск программ Windows
com.obsproject.Studio|OBS Studio|Запись экрана и трансляции
org.videolan.VLC|VLC|Проигрыватель видео и музыки
md.obsidian.Obsidian|Obsidian|Заметки
us.zoom.Zoom|Zoom|Видеозвонки
org.onlyoffice.desktopeditors|OnlyOffice|Офисный пакет
org.libreoffice.LibreOffice|LibreOffice|Документы, таблицы, презентации
com.brave.Browser|Brave|Браузер
com.google.Chrome|Google Chrome|Браузер
com.visualstudio.code|Visual Studio Code|Редактор кода
org.gimp.GIMP|GIMP|Редактор изображений
org.kde.krita|Krita|Рисование
org.qbittorrent.qBittorrent|qBittorrent|Торрент-клиент
com.github.tchx84.Flatseal|Flatseal|Разрешения программ Flathub
EOF
}

# ---- Flathub и другие хранилища flatpak ----
fp_have() { command -v flatpak >/dev/null 2>&1; }
fp_remote() { flatpak remote-add --user --if-not-exists flathub "$FLATHUB" >/dev/null 2>&1; }
fp_installed() { { timeout 4 flatpak list --user --app --columns=application,name; timeout 4 flatpak list --system --app --columns=application,name; } 2>/dev/null; }
fp_state() { if printf '%s\n' "$FP_HAVE" | grep -qxF -- "$1"; then echo installed; else echo available; fi; }
# каталог программ хранилищ скачивается один раз и потом раз в сутки
fp_refresh() {
  local stamp="$STATE/flatpak-appstream"
  if [ ! -e "$stamp" ] || [ -n "$(find "$stamp" -mmin +1440 2>/dev/null)" ] || [ "${1:-}" = force ]; then
    timeout 5 flatpak update --user --appstream >/dev/null 2>&1 && touch "$stamp"
  fi
}
# поиск средствами flatpak: имя<TAB>название<TAB>описание<TAB>хранилище
fp_search_local() {
  flatpak search --columns=application,name,description,remotes -- "$1" 2>/dev/null | head -n 25 |
    awk -F'\t' '$1 ~ /\./ { split($4, r, ","); print $1 "\t" $2 "\t" $3 "\t" (r[1] == "" ? "flathub" : r[1]) }'
}
# запасной путь: поиск на сайте flathub.org (когда локальный каталог не скачался)
fp_search_web() {
  command -v jq >/dev/null 2>&1 || return 0
  curl -fsS -m 12 -H 'Content-Type: application/json' \
       -d "$(jq -cn --arg q "$1" '{query: $q}')" https://flathub.org/api/v2/search 2>/dev/null |
    jq -r '.hits[]? | [.app_id, .name, (.summary // ""), "flathub"] | @tsv' 2>/dev/null | head -n 25
}
fp_search() {
  local q="$1" out
  fp_remote; fp_refresh
  out="$(fp_search_local "$q")"
  [ -n "$out" ] || out="$(fp_search_web "$q")"
  if [ -z "$out" ]; then
    curl -fsI -m 6 -o /dev/null https://dl.flathub.org 2>/dev/null \
      || row note flatpak - "Flathub недоступен" "нет связи с dl.flathub.org; подробности: win11-pkg doctor"
    return
  fi
  FP_HAVE="$(fp_installed | cut -f1)"
  printf '%s\n' "$out" | while IFS="$T" read -r id name desc remote; do
    src=flatpak; [ "$remote" = flathub ] || src="flatpak:$remote"
    row "$(fp_state "$id")" "$src" "$id" "${name:-$id}" "$desc"
  done
}

# ---- NixOS и свои источники Nix ----
nix_url() { awk -F'\t' -v n="$1" '$1 == n { print $2; exit }' "$NIX_SOURCES"; }
nix_state() {
  if grep -q "^$1$T" "$REC"; then echo installed
  elif [ -e "/run/current-system/sw/bin/${1##*.}" ]; then echo system
  else echo available; fi
}
valid_attr() { printf '%s' "$1" | grep -qE '^[A-Za-z0-9_.+-]{2,}$'; }

emit_catalog() {   # $1 - фильтр (пусто - всё)
  local q; q="$(printf '%s' "$1" | lower)"
  catalog | while IFS='|' read -r id name desc; do
    [ -z "$q" ] || printf '%s %s %s' "$id" "$name" "$desc" | lower | grep -qF -- "$q" || continue
    row "$(nix_state "$id")" nix "$id" "$name" "$desc"
  done
}
emit_flat_catalog() {
  fp_have || return 0
  FP_HAVE="$(printf '%s\n' "${FP_ROWS:-}" | cut -f1)"
  flat_catalog | while IFS='|' read -r id name desc; do row "$(fp_state "$id")" flatpak "$id" "$name" "$desc"; done
}
emit_installed() {
  local id name pname src
  printf '%s\n' "${FP_ROWS:-}" | while IFS="$T" read -r id name; do
    [ -n "$id" ] && row installed flatpak "$id" "${name:-$id}" ""
  done
  while IFS="$T" read -r id pname src; do
    [ -n "$id" ] || continue
    [ -z "$src" ] && catalog | grep -q "^$id|" && continue
    row installed "nix${src:+:$src}" "$id" "$id" ""
  done < "$REC"
  for f in "$APPIMAGES"/*.AppImage; do
    [ -f "$f" ] && row installed appimage "$f" "$(basename "$f" .AppImage)" "файл AppImage"
  done
}

install_nix() {   # источник имя
  local source="$1" id="$2" from="<nixpkgs>" before after new
  valid_attr "$id" || fail "недопустимое имя"
  if [ -n "$source" ]; then from="$(nix_url "$source")"; [ -n "$from" ] || fail "нет источника $source"; fi
  # несвободные программы (Discord, Steam, Chrome) разрешаем один раз
  if [ ! -e "$HOME/.config/nixpkgs/config.nix" ]; then
    mkdir -p "$HOME/.config/nixpkgs" && echo '{ allowUnfree = true; }' > "$HOME/.config/nixpkgs/config.nix"
  fi
  echo "Скачиваю $id из ${source:-NixOS}"
  before="$(nix-env -q 2>/dev/null | sort)"
  stream nix-env -f "$from" -iA "$id" || fail "не удалось установить $id (нет такого пакета или нет сети)"
  after="$(nix-env -q 2>/dev/null | sort)"
  new="$(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after") | head -n 1)"
  grep -v "^$id$T" "$REC" > "$REC.tmp"
  printf '%s\t%s\t%s\n' "$id" "${new:-${id##*.}}" "$source" >> "$REC.tmp"; mv "$REC.tmp" "$REC"
  echo "OK $id установлена"
}
remove_nix() {
  local id="$1" pname
  pname="$(grep "^$id$T" "$REC" | head -n 1 | cut -f2)"
  [ -n "$pname" ] || fail "$id установлена не отсюда"
  stream nix-env -e "$pname" || fail "не удалось удалить $id"
  grep -v "^$id$T" "$REC" > "$REC.tmp"; mv "$REC.tmp" "$REC"
  echo "OK $id удалена"
}
install_flatpak() {   # хранилище имя
  local remote="${1:-flathub}" id="$2"
  fp_have || fail "flatpak не установлен"
  [ "$remote" = flathub ] && fp_remote
  echo "Скачиваю $id из $remote"
  stream flatpak install --user -y --noninteractive "$remote" "$id" || fail "не удалось установить $id"
  echo "OK $id установлена"
}
remove_flatpak() {
  stream flatpak uninstall -y --noninteractive "$1" || fail "не удалось удалить $1"
  flatpak uninstall --user -y --noninteractive --unused >/dev/null 2>&1
  echo "OK $1 удалена"
}
# AppImage: файл копируется в свою папку и получает значок в "Пуске"
install_appimage() {
  local file="${1#file://}" name dest
  [ -f "$file" ] || fail "нет такого файла: $file"
  name="$(basename "$file")"; name="${name%.[Aa]pp[Ii]mage}"
  dest="$APPIMAGES/$name.AppImage"
  mkdir -p "$APPIMAGES" "$HOME/.local/share/applications"
  cp -f "$file" "$dest" && chmod +x "$dest" || fail "не удалось скопировать файл"
  printf '[Desktop Entry]\nType=Application\nName=%s\nExec=appimage-run "%s"\nIcon=application-x-executable\nCategories=Utility;\n' \
    "$name" "$dest" > "$HOME/.local/share/applications/win11-appimage-$name.desktop"
  echo "OK $name установлена"
}
remove_appimage() {
  local name; name="$(basename "$1" .AppImage)"
  case "$1" in "$APPIMAGES"/*) ;; *) fail "этот файл установлен не отсюда" ;; esac
  rm -f "$1" "$HOME/.local/share/applications/win11-appimage-$name.desktop"
  echo "OK $name удалена"
}

sources() {
  printf 'nix\tNixOS\tканал системы\t0\n'
  awk -F'\t' 'NF >= 2 { print "nix\t" $1 "\t" $2 "\t1" }' "$NIX_SOURCES"
  fp_have || return 0
  { flatpak remotes --user --columns=name,url; flatpak remotes --system --columns=name,url; } 2>/dev/null |
    awk -F'\t' 'NF >= 1 && !seen[$1]++ { print "flatpak\t" $1 "\t" $2 "\t" ($1 == "flathub" ? 0 : 1) }'
}
source_add() {   # вид имя адрес
  local kind="$1" name="$2" url="$3"
  printf '%s' "$name" | grep -qE '^[A-Za-z0-9_-]{2,30}$' || fail "имя источника: латинские буквы, цифры, - и _"
  case "$url" in https://*|http://*) ;; *) fail "адрес должен начинаться с https://" ;; esac
  case "$kind" in
    nix)
      grep -v "^$name$T" "$NIX_SOURCES" > "$NIX_SOURCES.tmp"
      printf '%s\t%s\n' "$name" "$url" >> "$NIX_SOURCES.tmp"; mv "$NIX_SOURCES.tmp" "$NIX_SOURCES" ;;
    flatpak)
      fp_have || fail "flatpak не установлен"
      stream flatpak remote-add --user --if-not-exists "$name" "$url" || fail "не удалось добавить хранилище"
      fp_refresh force ;;
    *) fail "вид источника: nix или flatpak" ;;
  esac
  echo "OK источник $name добавлен"
}
source_remove() {
  case "$1" in
    nix) grep -v "^$2$T" "$NIX_SOURCES" > "$NIX_SOURCES.tmp"; mv "$NIX_SOURCES.tmp" "$NIX_SOURCES" ;;
    flatpak) [ "$2" = flathub ] && fail "Flathub удалить нельзя"
             stream flatpak remote-delete --user --force "$2" || fail "не удалось удалить хранилище" ;;
    *) fail "вид источника: nix или flatpak" ;;
  esac
  echo "OK источник $2 удалён"
}

doctor() {
  echo "flatpak: $(command -v flatpak || echo 'не установлен (services.flatpak.enable)')"
  fp_have || return 0
  echo "версия: $(flatpak --version 2>&1)"
  echo "хранилища:"; { flatpak remotes --user --columns=name,url; flatpak remotes --system --columns=name,url; } 2>&1 | sed 's/^/  /'
  echo "связь с dl.flathub.org: $(curl -sI -m 8 -o /dev/null -w '%{http_code}' https://dl.flathub.org 2>&1)"
  echo "связь с flathub.org:    $(curl -sI -m 8 -o /dev/null -w '%{http_code}' https://flathub.org 2>&1)"
  echo "обновление каталога:"; flatpak update --user --appstream 2>&1 | tail -n 5 | sed 's/^/  /'
  echo "поиск \"discord\" (flatpak):"; flatpak search --columns=application,name discord 2>&1 | head -n 5 | sed 's/^/  /'
  echo "поиск \"discord\" (сайт):"; fp_search_web discord | head -n 3 | sed 's/^/  /'
}

case "${1:-}" in
  list) FP_ROWS=""; if fp_have; then FP_ROWS="$(fp_installed)"; fi; emit_installed; emit_catalog ""; emit_flat_catalog ;;
  search)
    q="${2:-}"
    emit_catalog "$q"
    # точное имя пакета, которого нет в каталоге: в NixOS и в каждом своём источнике
    if valid_attr "$q"; then
      catalog | grep -q "^$q|" || row "$(nix_state "$q")" nix "$q" "$q" "пакет NixOS с таким именем (если существует)"
      while IFS="$T" read -r name url; do
        [ -n "$name" ] && row available "nix:$name" "$q" "$q" "пакет с таким именем из источника $name"
      done < "$NIX_SOURCES"
    fi
    if fp_have && [ "${#q}" -ge 2 ]; then fp_search "$q"; fi ;;
  install|remove)
    action="$1"; src="${2:-}"; id="${3:-}"
    [ -n "$id" ] || fail "не указана программа"
    kind="${src%%:*}"; sub=""; case "$src" in *:*) sub="${src#*:}" ;; esac
    case "$action:$kind" in
      install:nix) install_nix "$sub" "$id" ;;
      install:flatpak) install_flatpak "$sub" "$id" ;;
      install:appimage) install_appimage "$id" ;;
      remove:nix) remove_nix "$id" ;;
      remove:flatpak) remove_flatpak "$id" ;;
      remove:appimage) remove_appimage "$id" ;;
      *) fail "неизвестный источник: $src" ;;
    esac ;;
  sources) sources ;;
  source)
    case "${2:-}" in
      add) source_add "${3:-}" "${4:-}" "${5:-}" ;;
      remove) source_remove "${3:-}" "${4:-}" ;;
      *) fail "source add|remove" ;;
    esac ;;
  doctor) doctor ;;
  upgrade)
    # обновление всех программ пользователя: одна строка с процентами вместо журнала
    bar() {
      while read -r tag pct rest; do
        [ "$tag" = PCT ] && printf '\r    %-12s %3d%%  %-40.40s' "$2" "$pct" "$rest"
      done
      printf '\r%70s\r' ""
    }
    rc=0
    if command -v flatpak >/dev/null 2>&1; then
      stream flatpak update --user -y --noninteractive | bar x Flathub; [ "${PIPESTATUS[0]}" -eq 0 ] || rc=1
    fi
    if [ -n "$(nix-env -q 2>/dev/null)" ]; then
      stream nix-env -u | bar x NixOS; [ "${PIPESTATUS[0]}" -eq 0 ] || rc=1
    fi
    if [ "$rc" -eq 0 ]; then echo "Программы обновлены"; else echo "Не всё обновилось, подробности: $PKG_LOG"; fi
    exit "$rc" ;;
  *) sed -n '1,9p' "$0" | sed 's/^# \{0,1\}//' ;;
esac
