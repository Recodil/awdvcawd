# Пример подключения к существующей конфигурации NixOS.
{ ... }:
{
  imports = [ ./win11-shell/win11-shell.nix ];
}
