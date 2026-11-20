# Оболочка в стиле Windows 11 для NixOS (niri + Quickshell + тема SDDM).
# Подключается из configuration.nix строкой:  imports = [ ./win11-shell/win11-shell.nix ];
{ pkgs, lib, config, options, ... }:

let
  # install.sh --safe создаёт файл safe-login: экран входа LightDM вместо SDDM.
  safe = builtins.pathExists ./safe-login;

  # тема экрана входа: QML из ./sddm + обои и шрифт значков из оболочки
  sddmTheme = pkgs.runCommand "win11-sddm-theme" { } ''
    dir=$out/share/sddm/themes/win11
    mkdir -p $dir
    cp ${./sddm}/* $dir/
    cp ${./shell/assets/wallpaper.jpg} $dir/wallpaper.jpg
    cp ${./shell/assets/FluentSystemIcons-Regular.ttf} $dir/icons.ttf
  '';
in
{
  imports = [ ./recovery.nix ./disk.nix ./drivers.nix ./niri-patch.nix ./zapret.nix ]
    ++ (if builtins.pathExists ./no-printing then [ ] else [ ./printing.nix ])
    ++ (if builtins.pathExists ./drivers-auto.nix then [ ./drivers-auto.nix ] else [ ]);

  # запуск программ в формате AppImage (их ставит "Параметры" - "Приложения")
  programs.appimage.enable = lib.mkDefault true;
  programs.appimage.binfmt = lib.mkDefault true;

  programs.niri.enable = true;

  # QML-файлы оболочки попадают в /etc/win11-shell
  environment.etc."win11-shell".source = ./shell;
  # список всех раскладок клавиатуры и их вариантов - для "Параметры" → "Время и язык"
  environment.etc."win11-xkb".source = "${pkgs.xkeyboard-config or pkgs.xkeyboard_config}/share";

  environment.systemPackages = with pkgs; [
    sddmTheme
    quickshell
    fd                     # поиск файлов (Win+S)
    xdg-utils
    xwayland-satellite     # X11-программы в niri
    brightnessctl          # яркость
    gammastep              # "Ночной свет"
    dconf                  # светлая/тёмная тема приложений
    gsettings-desktop-schemas   # без них программы не видят раскладку кнопок в заголовке
    curl                   # проверка выхода в интернет для значка сети
    swayidle               # автоблокировка
    alsa-utils             # amixer, speaker-test: проверка и починка звука (win11-sound)
    pulseaudio             # только команда pactl; сам звуковой сервер - PipeWire
    networkmanagerapplet   # значок сети в трее
    fluent-gtk-theme
    fluent-icon-theme
    bibata-cursors
  ];

  programs.dconf.enable = true;
  services.upower.enable = true;

  # Одиночное нажатие Win открывает "Пуск": keyd превращает короткое нажатие
  # левой клавиши Win в Win+F10, а удержание оставляет обычным модификатором.
  services.keyd = {
    enable = true;
    keyboards.default = {
      ids = [ "*" ];
      settings.main.leftmeta = "overload(meta, M-f10)";
    };
  };

  # Сжатый своп в оперативной памяти: помогает на машинах, где её мало.
  zramSwap.enable = lib.mkDefault (!(builtins.pathExists ./no-zram));

  # окно запроса пароля администратора (только в сеансе niri)
  systemd.user.services.win11-polkit-agent = {
    description = "Polkit agent for win11-shell";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    unitConfig.ConditionEnvironment = "XDG_CURRENT_DESKTOP=niri";
    serviceConfig = {
      ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
      Restart = "on-failure";
    };
  };

  # экран входа в стиле Windows 11 (в безопасном режиме - обычный LightDM)
  services.displayManager.sddm = lib.mkIf (!safe) {
    enable = true;
    package = pkgs.kdePackages.sddm;
    theme = "win11";
  };
  services.xserver.displayManager.lightdm.enable = lib.mkForce safe;   # mkForce: в вашем конфиге мог быть включён LightDM
  services.displayManager.defaultSession = "niri";

  # При включении и выключении - обычный текстовый экран Linux, без заставки:
  # так быстрее и видно, что происходит.
  boot.plymouth.enable = false;

  # Часовой пояс выбирается в "Параметрах" (timedatectl), поэтому в конфиге он не закреплён.
  # При первом запуске ставится московское время.
  time.timeZone = lib.mkForce null;
  # Языки программ, доступные в "Параметрах" → "Время и язык" (переводы самих программ ставятся вместе с ними).
  # Список подобран по файлу SUPPORTED из glibc: только записи вида "xx_YY.UTF-8/UTF-8".
  # Запись, которой там нет, ломает сборку ("unsupported locales"), поэтому языки, записанные
  # в glibc иначе (sr_RS, hi_IN, vi_VN, hy_AM, az_AZ, tt_RU, ky_KG, tg_TJ), сюда не входят.
  # Свои языки добавляются файлом /etc/nixos/win11-shell/extra-locales (по одной записи в строке,
  # например "hi_IN/UTF-8"); при ошибке сборки файл можно просто удалить.
  i18n = let
    base = map (l: "${l}.UTF-8/UTF-8") [
      "ru_RU" "en_US" "en_GB" "uk_UA" "be_BY" "kk_KZ" "de_DE" "fr_FR" "es_ES" "it_IT" "pt_BR" "pt_PT" "pl_PL"
      "tr_TR" "cs_CZ" "nl_NL" "sv_SE" "fi_FI" "nb_NO" "da_DK" "el_GR" "hu_HU" "ro_RO" "bg_BG" "he_IL"
      "ar_EG" "zh_CN" "zh_TW" "ja_JP" "ko_KR" "th_TH" "id_ID" "ka_GE" "lt_LT" "lv_LV" "et_EE"
    ];
    extra = if builtins.pathExists ./extra-locales
      then builtins.filter (l: builtins.isString l && builtins.match "[A-Za-z_@.0-9-]+/[A-Za-z0-9-]+" l != null)
             (builtins.split "[ \t\r\n]+" (builtins.readFile ./extra-locales))
      else [ ];
    list = lib.unique (base ++ extra);
  in
    # i18n.extraLocales появился в NixOS 25.05; на более старых выпусках используется supportedLocales
    if options.i18n ? extraLocales
    then { extraLocales = list; }
    else { supportedLocales = lib.unique ([ "${config.i18n.defaultLocale}/UTF-8" ] ++ list); };
  systemd.services.win11-timezone-init = {
    description = "Часовой пояс по умолчанию";
    wantedBy = [ "multi-user.target" ];
    before = [ "display-manager.service" ];
    unitConfig.ConditionPathExists = "!/etc/localtime";
    serviceConfig.Type = "oneshot";
    script = "ln -sf /etc/zoneinfo/Europe/Moscow /etc/localtime";
  };
  # смена пояса без запроса пароля для администраторов
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "org.freedesktop.timedate1.set-timezone" && subject.isInGroup("wheel")) {
        return polkit.Result.YES;
      }
    });
  '';
}
