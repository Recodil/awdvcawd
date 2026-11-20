# Оборудование: всё, что Linux умеет подхватывать сам, включено заранее.
# Сами драйверы входят в ядро и загружаются автоматически; здесь — прошивки и службы к ним.
{ config, lib, pkgs, ... }:

{
  # прошивки для Wi-Fi, Bluetooth, видеокарт, звука и т. д. (включая несвободные)
  hardware.enableRedistributableFirmware = true;
  hardware.enableAllFirmware = true;

  # обновления микрокода процессора — применяется только подходящий
  hardware.cpu.intel.updateMicrocode = lib.mkDefault true;
  hardware.cpu.amd.updateMicrocode = lib.mkDefault true;

  # графика: Mesa для Intel / AMD / nouveau, плюс 32-битные библиотеки для игр
  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;

  # Bluetooth (служба запускается, только когда есть адаптер)
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = false;

  # обновление прошивок устройств (команда: fwupdmgr update); запускается по требованию
  services.fwupd.enable = true;

  # флешки, телефоны, фотоаппараты в «Файлах»
  services.gvfs.enable = true;
  services.udisks2.enable = true;

  # программы для отчёта об оборудовании (bash doctor.sh)
  environment.systemPackages = [ pkgs.pciutils pkgs.usbutils ];
}
