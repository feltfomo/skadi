# _lib/furnish/files.nix -- turns already-resolved file entries into furnish
# declaration records. ownership is read before an entry reaches here and no
# claim key survives the trip.
{
  lib,
  contract,
}:
let
  # home-relative destinations belong to the people who live in those homes, so
  # a system principal takes none of them.
  homePrincipals =
    principals: builtins.filter (principal: principal.authority.scope == "user") principals;

  declarationFor =
    filesystemNamespace: principal: entry:
    {
      label = entry.label or "files[${entry.dest}]";
      inherit filesystemNamespace;
      inherit (principal) authority;
      # a user principal's managed root is that user's home, which is also what
      # the destination is written relative to.
      managedRoot = "/home/${principal.authority.identity}";
      destination = entry.dest;
      representation = contract.capabilities.symlink;
      source = {
        kind = "path";
        value = entry.src;
      };
    }
    // lib.optionalAttrs (entry ? provenance) { provenance.source = entry.provenance; };
in
{
  # one declaration per surviving entry per user principal on the host being
  # built. entries arrive already narrowed.
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
