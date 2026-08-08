{
  config,
  lib,
  pkgs,
  ...
}:
# aggregates every matugen-backed aspect's template entries into one config
# per renderer and principal. matugen has no include or merge mechanism, so a
# renderer's independent program declarations must converge before furnish
# publishes its config.toml.
let
  contract = import ../../furnish/contract.nix { inherit lib; };
  furnishFiles = import ../../furnish/files.nix { inherit lib contract; };
  axiom = import ../../axiom { inherit lib; };
  capability = import ./capabilities.nix;
  inherit (import ../report.nix { inherit lib; }) problem finish;

  candidates =
    lib.mapAttrsToList
      (name: path: {
        inherit name;
        adapter = import path { inherit lib; };
      })
      {
        caelestia = ./adapters/caelestia.nix;
        dms = ./adapters/dms.nix;
        end4-pc = ./adapters/end4-pc.nix;
        illogical-impulse = ./adapters/illogical-impulse.nix;
        noctalia = ./adapters/noctalia.nix;
      };

  # the matugen-backed renderers are the ones whose adapter says it needs the
  # runtime, not a second hand-kept list that drifts from the adapters
  observation = axiom.requirements.observe {
    required = [ capability.matugenRuntime ];
    inherit candidates;
    providedBy = entry: entry.adapter.capabilities;
  };

  adapters = builtins.listToAttrs (
    map (entry: {
      inherit (entry.candidate) name;
      value = entry.candidate.adapter;
    }) observation.qualified
  );

  cfg = config.lexicon.theme.matugen;

  groupKey =
    entry:
    axiom.canonical.join ":" [
      entry.renderer
      entry.filesystemNamespace
      entry.principal.authority.scope
      entry.principal.authority.identity
    ];
  groups = builtins.attrValues (builtins.groupBy groupKey cfg.entries);

  declarationsFor =
    entries:
    let
      first = builtins.head entries;
      adapter = adapters.${first.renderer};
      keyed = finish (
        axiom.registry.compile {
          registrations = entries;
          keyOf = entry: entry.registrationId;
          onDuplicate =
            id: _duplicates:
            problem {
              code = "theme-registration-duplicate";
              message = "has duplicate registration id ${id} for ${first.filesystemNamespace} (${first.principal.authority.identity})";
              primary.label = "theme.${first.renderer}";
            };
        }
      );
    in
    builtins.seq keyed (
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
      }
    );
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
