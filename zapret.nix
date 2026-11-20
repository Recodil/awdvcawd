# Обход замедления YouTube и Discord: github.com/kartavkun/zapret-discord-youtube.
# Автор даёт модуль только для flakes; здесь он подключается без них, конфиг править не нужно.
# Управление: команда win11-zapret (status, check, test, list, set, on, off).
#   zapret-config   имя стратегии (по умолчанию general); меняет "win11-zapret set <имя>"
#   zapret-fake     подставной пакет для голосовых звонков Discord: имя .bin из набора Flowseal;
#                   меняет "win11-zapret fake <имя>"
#   zapret-game     режим игрового фильтра (udp, tcp, all); меняет "win11-zapret game <режим>"
#   no-zapret       файл-выключатель; создаёт "win11-zapret disable" или установщик при сбое сборки
{ pkgs, lib, ... }:

let
  enabled = !builtins.pathExists ./no-zapret;
  configName =
    if builtins.pathExists ./zapret-config
    then lib.removeSuffix "\n" (builtins.readFile ./zapret-config)
    else "general";
  marker = file: default:
    if builtins.pathExists file then lib.removeSuffix "\n" (builtins.readFile file) else default;
  # Голос Discord идёт по UDP. У многих провайдеров стандартный подставной пакет не помогает
  # ("RTC connecting" без конца), а пакет под lemanapro.ru проходит - он и взят по умолчанию.
  discordFake = marker ./zapret-fake "quic_initial_lemana_pro.bin";
  gameFilter = marker ./zapret-game "off";
  # исходники скачиваются при сборке системы и хранятся в /nix/store; раз в час проверяется свежая версия
  src = builtins.fetchTarball "https://github.com/kartavkun/zapret-discord-youtube/archive/main.tar.gz";
  flowseal = builtins.fetchTarball "https://github.com/Flowseal/zapret-discord-youtube/archive/main.tar.gz";
  tool = pkgs.writeShellScriptBin "win11-zapret" (builtins.readFile ./scripts/zapret.sh);
  # Смена стратегии без пересборки: служба запускается через runner, который берёт выбор
  # из /var/lib/win11-zapret; записывает выбор rootTool (для группы wheel - без пароля).
  runner = pkgs.writeShellScript "win11-zapret-run" (builtins.readFile ./scripts/zapret-run.sh);
  rootTool = pkgs.writeShellScriptBin "win11-zapret-root" (builtins.readFile ./scripts/zapret-root.sh);
in
{
  imports = if enabled then [ (import "${src}/nixos/module.nix" { zapret-flowseal = flowseal; }) ] else [ ];

  config = (if enabled then { } else {
    environment.systemPackages = [ tool pkgs.curl ];
  }) // (if enabled then {
    services.zapret-discord-youtube = {
      enable = true;
      inherit configName;
      activeDiscordFake = if discordFake == "default" then null else discordFake;
      gameFilter = if gameFilter == "off" then null else gameFilter;
      testTools.enable = true;      # sudo zapret-test-strategies - подбор стратегии
    };
    environment.systemPackages = [ tool pkgs.curl rootTool ];
    systemd.services.zapret-discord-youtube.serviceConfig = {
      ExecStart = lib.mkForce "${runner} start";
      ExecStop = lib.mkForce "${runner} stop";
      ExecReload = lib.mkForce "${runner} restart";
      # служба заперта (ProtectSystem=strict): без этого копия набора в /run не создаётся
      RuntimeDirectory = "win11-zapret";
      RuntimeDirectoryPreserve = "yes";
    };
    security.sudo.extraRules = [{
      groups = [ "wheel" ];
      commands = [{ command = "/run/current-system/sw/bin/win11-zapret-root"; options = [ "NOPASSWD" ]; }];
    }];
  } else { });
}
