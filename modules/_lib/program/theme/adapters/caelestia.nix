{ lib }:
let
  capability = import ../capabilities.nix;
in
{
  capabilities = [ capability.blockFiles ];
  templateRoot = ".config/caelestia/templates";
  templateNameOf = entry: "${entry.registrationId}-${entry.placedAs}";
  filesFor =
    {
      pkgs,
      blockId,
      entries,
      templateNameOf,
    }:
    let
      orderedEntries = builtins.sort (
        left: right: builtins.lessThan left.registrationId right.registrationId
      ) entries;
      reloadEntries = builtins.filter (entry: entry.reload != null) orderedEntries;
      installCommands = lib.concatMapStringsSep "\n" (entry: ''
        ${pkgs.coreutils}/bin/install -Dm644 \\
          "$HOME/.local/state/caelestia/theme/${templateNameOf entry}" \\
          "$HOME/${entry.output}"
      '') orderedEntries;
      reloadCommands = lib.concatMapStringsSep "\n" (entry: entry.reload) reloadEntries;
    in
    [
      {
        dest = ".config/caelestia/theme-hooks/${blockId}";
        src = pkgs.writeShellScript "caelestia-${blockId}-theme-hook" ''
          set -eu

          ${installCommands}
          ${reloadCommands}
        '';
        provenance = "modules/_lib/program.nix";
      }
    ];
}
