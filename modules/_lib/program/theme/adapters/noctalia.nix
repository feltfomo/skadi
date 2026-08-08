{ lib }:
let
  capability = import ../capabilities.nix;
in
{
  acceptsNative = true;
  capabilities = [
    capability.nativeBlocks
    capability.blockFiles
  ];
  templateRoot = ".config/noctalia/templates";
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
          input_path = "~/.config/noctalia/templates/${templateNameOf entry}";
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
        dest = ".config/noctalia/${blockId}.toml";
        src = (pkgs.formats.toml { }).generate "noctalia-${blockId}.toml" {
          theme.templates.user = registrations;
        };
        provenance = "modules/_lib/program.nix";
      }
    ];
}
