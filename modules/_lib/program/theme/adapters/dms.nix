{ lib }:
{
  acceptsNative = true;
  templateRoot = ".config/matugen/dms/templates";
  templateNameOf = entry: "${entry.subdir}${entry.placedAs}";
  filesFor =
    {
      pkgs,
      blockId,
      entries,
      templateNameOf,
    }:
    let
      registrationOf =
        entry:
        entry.native
        // {
          input_path = "~/.config/matugen/dms/templates/${templateNameOf entry}";
          output_path = "~/${entry.output}";
        }
        // lib.optionalAttrs (entry.reload != null) { post_hook = entry.reload; };
      registrations = builtins.listToAttrs (
        map (entry: {
          name = entry.registrationId;
          value = registrationOf entry;
        }) entries
      );
    in
    [
      {
        dest = ".config/matugen/dms/configs/${blockId}.toml";
        src = (pkgs.formats.toml { }).generate "dms-${blockId}.toml" {
          templates = registrations;
        };
        provenance = "modules/_lib/program.nix";
      }
    ];
}
