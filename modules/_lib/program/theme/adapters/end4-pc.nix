{ lib }:
let
  capability = import ../capabilities.nix;
in
{
  capabilities = [
    capability.nativeBlocks
    capability.matugenRuntime
  ];
  runtime = "matugen";
  configDestination = ".config/end4-pc/matugen/config.toml";
  templateRoot = ".config/end4-pc/matugen/templates";
  templateNameOf = entry: "${entry.subdir}${entry.placedAs}";
  filesFor = _: [ ];
  registrationOf =
    entry:
    let
      home = lib.removeSuffix "/" (
        entry.principal.managedRoot or "/home/${entry.principal.authority.identity}"
      );
    in
    entry.native
    // {
      input_path = "${home}/.config/end4-pc/matugen/templates/${entry.subdir}${entry.placedAs}";
      output_path = "${home}/${entry.output}";
    }
    // lib.optionalAttrs (entry.reload != null) { post_hook = entry.reload; };
}
