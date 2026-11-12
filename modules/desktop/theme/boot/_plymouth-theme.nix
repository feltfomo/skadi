# the plymouth splash. its images come from the fallback theme's plymouth/, and the script prefers
# the live ones on the esp. the two colors it still draws itself, the surface behind the backdrop and
# the error messages, are written ahead of the script as globals.
{
  lib,
  runCommand,
  palette,
  fallback,
}:
let
  colors = import ./_colors.nix { inherit lib; };
  globals =
    lib.concatMapStrings
      (
        role:
        let
          channels = lib.splitString ", " (colors.unit palette.${role});
        in
        lib.concatImapStrings (
          index: value: "color_${role}[${toString (index - 1)}] = ${value};\n"
        ) channels
      )
      [
        "surface"
        "error"
      ];
  directory = "share/plymouth/themes/skadi";
in
runCommand "skadi-plymouth-theme"
  {
    inherit globals;
    passAsFile = [ "globals" ];
  }
  ''
    set -euo pipefail
    mkdir -p "$out/${directory}"
    cat "$globalsPath" ${./plymouth/skadi.script} > "$out/${directory}/skadi.script"
    cp ${fallback}/plymouth/*.png "$out/${directory}/"
    cat > "$out/${directory}/skadi.plymouth" <<EOF
    [Plymouth Theme]
    Name=Skadi
    Description=The host name and disk password on the Skadi palette
    ModuleName=script

    [script]
    ImageDir=$out/${directory}
    ScriptFile=$out/${directory}/skadi.script
    EOF
  ''
