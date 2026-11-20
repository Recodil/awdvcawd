# То, без чего оболочка не работает, но что обычно задаётся в configuration.nix.
# Подключается установщиком на компьютерах, где оболочка ставится впервые, рядом с вашим
# прежним конфигом (configuration-base.nix). Почти всё здесь - значения по умолчанию:
# то, что написано в вашем конфиге, главнее.
{ config, options, pkgs, lib, ... }:

{
  nixpkgs.config.allowUnfree = true;   # прошивки Wi-Fi, видеокарт и т. п. (drivers.nix)

  # сеть: NetworkManager, если вы не настроили Wi-Fi через wpa_supplicant
  networking.networkmanager.enable = lib.mkDefault (!config.networking.wireless.enable);

  # X-сервер нужен экрану входа
  services.xserver.enable = lib.mkDefault true;

  # звук
  services.pulseaudio.enable = lib.mkDefault false;
  security.rtkit.enable = lib.mkDefault true;
  services.pipewire = {
    enable = lib.mkDefault true;
    alsa.enable = lib.mkDefault true;
    pulse.enable = lib.mkDefault true;
  };

  # экран входа - SDDM из win11-shell.nix; GDM, если он был включён, выключается
  services.displayManager = lib.optionalAttrs (options.services.displayManager ? gdm) {
    gdm.enable = lib.mkForce false;
  };

  programs.firefox.enable = lib.mkDefault true;
  environment.systemPackages = with pkgs; [
    kitty                  # терминал (Win+T, "Выполнить", "Центр управления")
    nautilus               # "Проводник" (Win+E)
    mission-center         # диспетчер задач (Ctrl+Shift+Esc)
    gnome-text-editor      # "Блокнот"
    gnome-calculator       # "Калькулятор"
    git
    vlc
  ];

  # Flatpak и магазин Flathub
  # файл no-flatpak (ответ "только NixOS" при установке) оставляет систему без него
  services.flatpak.enable = lib.mkDefault (!(builtins.pathExists ./no-flatpak));
  xdg.portal.enable = lib.mkDefault true;
  systemd.services.flathub-remote = lib.mkIf config.services.flatpak.enable {
    description = "Add the Flathub remote for Flatpak";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = [ pkgs.flatpak ];
    serviceConfig = { Type = "oneshot"; Restart = "on-failure"; RestartSec = 60; };
    script = "flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo";
  };

  fonts.packages = with pkgs; [ inter noto-fonts noto-fonts-cjk-sans noto-fonts-color-emoji ];
}
