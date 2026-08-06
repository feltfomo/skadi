{
  config,
  lib,
  pkgs,
  ...
}:
# Aggregates every Matugen-backed aspect's template entries into one config
# per renderer and principal. Matugen has no include or merge mechanism, so a
# renderer's independent program declarations must converge before furnish
# publishes its config.toml.
let
  contract = import ../../furnish/contract.nix { inherit lib; };
  furnishFiles = import ../../furnish/files.nix { inherit lib contract; };
  adapters = {
    dms = import ./adapters/dms.nix { inherit lib; };
    illogical-impulse = import ./adapters/illogical-impulse.nix { inherit lib; };
  };
  cfg = config.lexicon.theme.matugen;

  duplicateValues =
    values:
    builtins.attrNames (
      lib.filterAttrs (_: group: builtins.length group > 1) (builtins.groupBy (value: value) values)
    );

  groupKey =
    entry:
    "${entry.renderer}:${entry.filesystemNamespace}:${entry.principal.authority.scope}:${entry.principal.authority.identity}";
  groups = builtins.attrValues (builtins.groupBy groupKey cfg.entries);

  declarationsFor =
    entries:
    let
      first = builtins.head entries;
      adapter = adapters.${first.renderer};
      ids = map (entry: entry.registrationId) entries;
      dupIds = duplicateValues ids;
    in
    if dupIds != [ ] then
      throw "theme.${first.renderer} has duplicate registration ids for ${first.filesystemNamespace} (${first.principal.authority.identity}): ${lib.concatStringsSep ", " dupIds}"
    else
      furnishFiles.mkDeclarations {
        inherit (first) filesystemNamespace;
        principals = [ first.principal ];
        files = [
          {
            dest = adapter.configDestination;
            src = (pkgs.formats.toml { }).generate "${first.renderer}-matugen-config" {
              config = { };
              templates = builtins.listToAttrs (
                map (entry: {
                  name = entry.registrationId;
                  value = adapter.registrationOf entry;
                }) entries
              );
            };
            provenance = "modules/_lib/program.nix";
          }
        ];
      };
in
{
  options.lexicon.theme.matugen.entries = lib.mkOption {
    type = lib.types.listOf lib.types.attrs;
    default = [ ];
    description = "Normalized Matugen template entries collected across program aspects and grouped by renderer and principal.";
  };

  config = lib.mkIf (cfg.entries != [ ]) {
    lexicon.furnish.declarations = builtins.concatMap declarationsFor groups;
  };
}
