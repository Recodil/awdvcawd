# Печать и сканирование - общий вариант для любого принтера.
# Драйверы для самых распространённых моделей уже включены; современные сетевые принтеры
# (AirPrint / IPP Everywhere) и МФУ находятся сами. Добавить принтер: "Центр управления" → "Добавить принтер"
# или команда win11-printfix add. Проверка и починка: win11-printfix [fix].
#
{ pkgs, lib, ... }:

{
  services.printing = {
    enable = true;
    drivers = with pkgs; [
      gutenprint     # Canon, Epson, Lexmark и сотни других
      hplip          # HP (без фирменного модуля; он нужен только некоторым моделям LaserJet)
      splix          # Samsung, часть Xerox и Dell
      brlaser        # Brother
    ];
  };

  # поиск принтеров и сканеров в локальной сети
  services.avahi = {
    enable = lib.mkDefault true;
    nssmdns4 = lib.mkDefault true;
    openFirewall = lib.mkDefault true;
  };
  # принтеры и МФУ по USB без драйвера (IPP-over-USB)
  services.ipp-usb.enable = lib.mkDefault true;

  hardware.sane = {
    enable = true;
    extraBackends = [ pkgs.sane-airscan pkgs.hplip ];
  };

  # окно "Принтеры": добавление и настройка
  programs.system-config-printer.enable = lib.mkDefault true;
  environment.systemPackages = [ pkgs.simple-scan ];
}
