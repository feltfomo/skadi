# shared theme design. load with `--load-path ${pkgs.skadi-theme-design}/share/sass`.
{ lib, ... }:
{
  # the approved dark palette. themes read it until the live palette exists, and the boot stages
  # read it always, since they run before anything can generate one.
  options.skadi.fallbackPalette = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    readOnly = true;
    default = lib.importJSON ./fallback.json;
    description = "Palette roles as #rrggbb, from fallback.json.";
  };

  config.skadi.packages.skadi-theme-design = ./_package.nix;
}
