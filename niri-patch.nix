# Кнопка «Свернуть» в заголовках окон.
# В niri нет сворачивания, и он сообщает программам, что кнопка не нужна. Здесь niri собирается
# с двумя маленькими правками: программам разрешено показывать кнопку, а нажатие передаётся
# оболочке (окно уходит на скрытый рабочий стол и остаётся на панели задач).
# Цена: niri компилируется на вашем компьютере (долго, только при установке и при обновлении niri).
# install.sh --no-niri-patch (или файл no-niri-patch) отключает это.
{ pkgs, lib, ... }:

let
  enabled = !builtins.pathExists ./no-niri-patch;
  minimize = pkgs.writeShellScriptBin "win11-minimize" ''
    exec niri msg action move-window-to-workspace --window-id "$1" --focus false min
  '';
in
{
  environment.systemPackages = [ minimize ];

  nixpkgs.overlays = lib.optional enabled (final: prev: {
    niri = prev.niri.overrideAttrs (old: {
      postPatch = (old.postPatch or "") + ''
        sed -i '/^impl XdgShellHandler for State {$/r ${./niri-minimize.rs}' src/handlers/xdg_shell.rs
        sed -i 's/^\( *\)\[WmCapabilities::Fullscreen/\1[WmCapabilities::Minimize, WmCapabilities::Fullscreen/' src/niri.rs
        grep -q 'win11-minimize' src/handlers/xdg_shell.rs
        grep -q 'WmCapabilities::Minimize' src/niri.rs
      '';
      doCheck = false;   # тесты niri идут долго и к правке не относятся
    });
  });
}
