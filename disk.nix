# Не меняет разметку, файловые системы и планировщики накопителей.
{ lib, ... }:
{
  nix.optimise.automatic = lib.mkIf (builtins.pathExists ./optimize-nix-store) (lib.mkDefault true);
  nix.optimise.dates = lib.mkIf (builtins.pathExists ./optimize-nix-store) (lib.mkDefault [ "weekly" ]);
}
