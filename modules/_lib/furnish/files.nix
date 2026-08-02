# turns resolved file entries into furnish declarations
# ownership is read before an entry reaches this layer
{
  lib,
  contract,
}:
let
  # home-relative destinations belong only to user principals
  homePrincipals =
    principals: builtins.filter (principal: principal.authority.scope == "user") principals;

  declarationFor =
    filesystemNamespace: principal: entry:
    {
      label = entry.label or "files[${entry.dest}]";
      inherit filesystemNamespace;
      inherit (principal) authority;
      # an explicit root supports nonstandard homes without changing current principals
      managedRoot = principal.managedRoot or "/home/${principal.authority.identity}";
      destination = entry.dest;
      # an absent representation retains the original symlink behavior
      representation = entry.representation or contract.capabilities.symlink;
      source = {
        kind = "path";
        value = entry.src;
      };
    }
    # core supplies the default conflict policy after selection
    // lib.optionalAttrs (entry ? onConflict) { inherit (entry) onConflict; }
    // lib.optionalAttrs (entry ? provenance) { provenance.source = entry.provenance; };
in
{
  # emit one declaration per entry and selected user principal
  mkDeclarations =
    {
      filesystemNamespace,
      principals,
      files ? [ ],
    }:
    builtins.concatMap (principal: map (declarationFor filesystemNamespace principal) files) (
      homePrincipals principals
    );
}
