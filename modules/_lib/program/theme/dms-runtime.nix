{
  config,
  lib,
  pkgs,
  ...
}:
# Aggregates every aspect's theme.dms template entries into ONE
# ~/.config/matugen/config.toml per principal. matugen only reads a single
# config file (no include/merge support), so this can't be emitted per-aspect
# -- program.nix runs once per aspect (nvim.nix, kitty.nix, ...), and each one
# independently trying to own .config/matugen/config.toml is exactly the
# collision furnish's collision detection caught.
#
# Imported once per aspect from program.nix, same as furnish/runtime.nix, but
# -- like that file -- the module system applies it once regardless of import
# count, so `config` below always sees every aspect's contribution already
# merged into cfg.entries before it computes anything.
let
  contract = import ../../furnish/contract.nix { inherit lib; };
  furnishFiles = import ../../furnish/files.nix { inherit lib contract; };
  adapter = import ./adapters/dms.nix { inherit lib; };
  cfg = config.lexicon.theme.dms;

  duplicateValues =
    values:
    builtins.attrNames (
      lib.filterAttrs (_: group: builtins.length group > 1) (builtins.groupBy (value: value) values)
    );

  # one group per (host, principal): a distinct config.toml destination.
  groupKey =
    entry:
    "${entry.filesystemNamespace}:${entry.principal.authority.scope}:${entry.principal.authority.identity}";
  groups = builtins.attrValues (builtins.groupBy groupKey cfg.entries);

  declarationsFor =
    entries:
    let
      first = builtins.head entries;
      ids = map (entry: entry.registrationId) entries;
      dupIds = duplicateValues ids;
    in
    if dupIds != [ ] then
      throw "theme.dms has duplicate registration ids for ${first.filesystemNamespace} (${first.principal.authority.identity}): ${lib.concatStringsSep ", " dupIds}"
    else
      furnishFiles.mkDeclarations {
        inherit (first) filesystemNamespace;
        principals = [ first.principal ];
        files = [
          {
            dest = ".config/matugen/config.toml";
            src = (pkgs.formats.toml { }).generate "matugen-config" {
              # matugen's serde schema: `templates` and `config` are both
              # top-level fields. Templates are NOT nested under `config`
              # -- the DankLinux docs phrasing "defined under the [config]
              # section" refers to the config *file*, not the TOML table.
              # Verify against:
              #   matugen color hex "#xxxxxx" --config <path>
              # Empty [config] is harmless but documented as required by
              # older matugen builds; 4.1.0 accepts its absence too.
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
  options.lexicon.theme.dms.entries = lib.mkOption {
    type = lib.types.listOf lib.types.attrs;
    default = [ ];
    description = "Normalized theme.dms template entries, collected from every aspect that declares one and merged here into a single ~/.config/matugen/config.toml per principal.";
  };

  config = lib.mkIf (cfg.entries != [ ]) {
    lexicon.furnish.declarations = builtins.concatMap declarationsFor groups;
  };
}
