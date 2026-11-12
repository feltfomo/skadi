# the boot theme in the fallback palette: grub/ and plymouth/, used until the live theme is rendered
# and whenever it's missing.
{
  lib,
  runCommand,
  skadi-boot-theme,
  palette,
  hostName,
  resolution,
}:
runCommand "skadi-boot-theme-${hostName}"
  {
    palette = builtins.toJSON palette;
    passAsFile = [ "palette" ];
  }
  ''
    ${lib.getExe skadi-boot-theme} --palette "$palettePath" --host ${lib.escapeShellArg hostName} \
      --width ${toString resolution.width} --height ${toString resolution.height} "$out"
  ''
