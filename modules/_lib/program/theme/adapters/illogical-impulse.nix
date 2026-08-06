{ lib }:
{
  acceptsNative = true;
  runtime = "matugen";
  configDestination = ".config/illogical-impulse/matugen/config.toml";
  templateRoot = ".config/illogical-impulse/matugen/templates";
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
      input_path = "${home}/.config/illogical-impulse/matugen/templates/${entry.subdir}${entry.placedAs}";
      output_path = "${home}/${entry.output}";
    }
    // lib.optionalAttrs (entry.reload != null) { post_hook = entry.reload; };
}
