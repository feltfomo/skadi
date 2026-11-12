# the boot menu in the fallback palette, the theme grub uses until the live one is rendered and
# whenever it's missing.
{
  lib,
  runCommand,
  skadi-grub-theme,
  palette,
  hostName,
  resolution,
}:
runCommand "skadi-grub-theme-${hostName}"
  {
    palette = builtins.toJSON palette;
    passAsFile = [ "palette" ];
  }
  ''
    ${lib.getExe skadi-grub-theme} --palette "$palettePath" --host ${lib.escapeShellArg hostName} \
      --width ${toString resolution.width} --height ${toString resolution.height} "$out"
  ''
