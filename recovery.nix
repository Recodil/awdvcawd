# Самопроверка и автоматический возврат прежней системы. См. scripts/.
{ config, pkgs, ... }:

let
  shellRun = pkgs.writeShellScriptBin "win11-shell-run" (builtins.readFile ./scripts/shell-run.sh);
  pkg = pkgs.writeShellScriptBin "win11-pkg" (builtins.readFile ./scripts/pkg.sh);
  updater = pkgs.writeShellScriptBin "win11-updater" (builtins.readFile ./scripts/updater.sh);
  # значок в "Пуске"; архив можно открыть и через "Открыть с помощью"
  updaterItem = pkgs.makeDesktopItem {
    name = "win11-updater";
    desktopName = "Обновление оболочки";
    comment = "Установить новую версию из архива";
    exec = "win11-updater run %f";
    icon = "system-software-update";
    categories = [ "System" ];
    mimeTypes = [ "application/zip" ];
  };
  # Все команды доступны из любого места: win11 <имя> или win11-<имя>.
  win11 = pkgs.writeShellScriptBin "win11" (builtins.readFile ./scripts/win11.sh);
  fromKit = name: file: pkgs.writeShellScriptBin name ''
    f=/etc/nixos/win11-shell-kit/${file}
    [ -e "$f" ] || { echo "Нет файла $f - установите оболочку заново (bash install.sh из архива)." >&2; exit 1; }
    exec ${pkgs.bash}/bin/bash "$f" "$@"
  '';
  doctor = fromKit "win11-doctor" "doctor.sh";
  installer = fromKit "win11-install" "install.sh";
  shutdownWin = pkgs.writeShellScriptBin "win11-shutdown" (builtins.readFile ./scripts/shutdown.sh);
  printfix = pkgs.writeShellScriptBin "win11-printfix" (builtins.readFile ./scripts/printfix.sh);
  lists = pkgs.writeShellScriptBin "win11-lists" (builtins.readFile ./scripts/lists.sh);
  pack = pkgs.writeShellScriptBin "win11-pack" (builtins.readFile ./scripts/pack.sh);
  drivers = pkgs.writeShellScriptBin "win11-drivers" (builtins.readFile ./scripts/drivers.sh);
  sound = pkgs.writeShellScriptBin "win11-sound" (builtins.readFile ./scripts/sound.sh);
  updates = pkgs.writeShellScriptBin "win11-updates" (builtins.readFile ./scripts/updates.sh);
  btBattery = pkgs.writeShellScriptBin "win11-bt-battery" (builtins.readFile ./scripts/bt-battery.sh);
  softwareCenter = pkgs.writeShellScriptBin "win11-software-center" (builtins.readFile ./scripts/software-center.sh);
  # "Параметры" и "Центр обновления" - окна оболочки; в "Пуске" и на панели задач это обычные приложения
  appIcons = pkgs.runCommand "win11-app-icons" { } ''
    dir=$out/share/icons/hicolor/scalable/apps
    mkdir -p $dir
    cp ${./shell/assets/app-settings.svg} $dir/win11-settings.svg
    cp ${./shell/assets/app-updates.svg} $dir/win11-updates.svg
    cp ${./shell/assets/app-taskmgr.svg} $dir/win11-taskmgr.svg
    cp ${./shell/assets/app-store.svg} $dir/win11-store.svg
  '';
  settingsItem = pkgs.makeDesktopItem {
    name = "win11-settings";
    desktopName = "Параметры";
    comment = "Настройка оболочки и системы";
    exec = "win11 settings";
    icon = "win11-settings";
    categories = [ "System" "Settings" ];
  };
  updatesItem = pkgs.makeDesktopItem {
    name = "win11-updates";
    desktopName = "Центр обновления Windows";
    comment = "Обновление системы, программ и драйверов";
    exec = "win11 updates";
    icon = "win11-updates";
    categories = [ "System" ];
  };
  taskmgr = pkgs.writeShellScriptBin "win11-taskmgr" (builtins.readFile ./scripts/taskmgr.sh);
  storeItem = pkgs.makeDesktopItem {
    name = "win11-store";
    desktopName = "Microsoft Store";
    comment = "Магазин приложений и установка программ";
    exec = "win11 store";
    icon = "win11-store";
    categories = [ "System" "PackageManager" ];
  };
  taskmgrItem = pkgs.makeDesktopItem {
    name = "win11-taskmgr";
    desktopName = "Диспетчер задач";
    comment = "Процессы, производительность, автозагрузка и службы";
    exec = "qs -p /etc/win11-shell ipc call shell taskmgr";
    icon = "win11-taskmgr";
    categories = [ "System" "Monitor" ];
  };
  hubItem = pkgs.makeDesktopItem {
    name = "win11-hub";
    desktopName = "Центр управления";
    comment = "Интернет, печать, обновление и починка - кнопками";
    exec = "win11 hub";
    icon = "preferences-system";
    categories = [ "System" "Settings" ];
  };
  mem = pkgs.writeShellScriptBin "win11-mem" (builtins.readFile ./scripts/mem.sh);
  recovery = pkgs.writeShellScriptBin "win11-recovery" (builtins.readFile ./scripts/recovery.sh);
  sessionCheck = pkgs.writeShellScriptBin "win11-session-check" (builtins.readFile ./scripts/session-check.sh);
  # win11-update - обновление одной командой (см. update.sh в комплекте)
  update = pkgs.writeShellScriptBin "win11-update" ''
    exec ${pkgs.bash}/bin/bash /etc/nixos/win11-shell-kit/update.sh "$@"
  '';
  watchdog = pkgs.writeShellScript "win11-trial-watchdog" (builtins.readFile ./scripts/trial-watchdog.sh);
in
{
  environment.systemPackages = [ shellRun sessionCheck update updater updaterItem mem pkg win11 doctor installer shutdownWin printfix lists pack hubItem drivers sound updates btBattery softwareCenter storeItem appIcons settingsItem updatesItem taskmgr taskmgrItem recovery pkgs.unzip pkgs.libnotify pkgs.jq pkgs.curl ];

  # shutdown /r /t 500 в терминале - как в Windows; обычные параметры Linux (shutdown -h now) работают по-прежнему
  environment.shellAliases.shutdown = "win11-shutdown";

  systemd.tmpfiles.rules = [
    "d /run/win11-shell 1777 root root -"
    "d /var/lib/win11-shell 0755 root root -"
    "d /var/lib/win11-shell/faces 1777 root root -"   # аватарки: их читает и экран входа
    "d /var/log/win11-shell 0755 root root -"
  ];

  # Новый архив в "Загрузках" или на рабочем столе - открывается окно обновления.
  systemd.user.paths.win11-updater = {
    wantedBy = [ "default.target" ];
    pathConfig = {
      PathChanged = [ "%h/Downloads" "%h/Загрузки" "%h/Desktop" ];
      Unit = "win11-updater.service";
    };
  };
  systemd.user.services.win11-updater = {
    description = "Поиск нового архива оболочки";
    serviceConfig = { Type = "oneshot"; ExecStart = "${updater}/bin/win11-updater watch"; };
  };

  systemd.services.win11-trial = {
    description = "Win11 shell: trial run watchdog with automatic rollback";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-tmpfiles-setup.service" ];
    path = [ config.nix.package pkgs.procps ];
    restartIfChanged = false;
    stopIfChanged = false;
    serviceConfig = {
      Type = "simple";
      ExecStart = watchdog;
    };
  };
}
