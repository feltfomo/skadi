# the plymouth splash. the script reads the palette as globals written ahead of it, so the scene
# stays plain script and only the colors come from nix.
{
  lib,
  runCommand,
  imagemagick,
  palette,
  hostName,
}:
let
  colors = import ./_colors.nix { inherit lib; };
  roles = [
    "on_surface_variant"
    "on_surface"
    "surface"
    "warning"
    "error"
  ];
  globals = ''
    host_name = "${hostName}";
  ''
  + lib.concatMapStrings (
    role:
    let
      channels = lib.splitString ", " (colors.unit palette.${role});
    in
    lib.concatImapStrings (
      index: value: "color_${role}[${toString (index - 1)}] = ${value};\n"
    ) channels
  ) roles;
  directory = "share/plymouth/themes/skadi";
in
runCommand "skadi-plymouth-theme"
  {
    nativeBuildInputs = [ imagemagick ];
    inherit globals;
    passAsFile = [ "globals" ];
  }
  ''
    set -euo pipefail
    mkdir -p "$out/${directory}"
    cat "$globalsPath" ${./plymouth/skadi.script} > "$out/${directory}/skadi.script"
    magick -size 560x56 xc:none \
      -fill '${palette.surface_container_high}' -stroke '${palette.outline_variant}' -strokewidth 2 \
      -draw "roundrectangle 1,1,558,54,6,6" "$out/${directory}/field.png"
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
