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
      # representation travels with the entry. an entry that names none is a
      # symlink, which is what every entry was before this layer could carry
      # anything else, so the declarations already in service are unchanged.
      representation = entry.representation or contract.capabilities.symlink;
      source = {
        kind = "path";
        value = entry.src;
      };
    }
    # onConflict is emitted only when the entry names one, rather than defaulted
    # here. core's materialize already supplies contract.conflictPolicies.error
    # for a declaration that carries none, and writing that default twice would
    # put a key on 29 declarations that do not have one today.
    // lib.optionalAttrs (entry ? onConflict) { inherit (entry) onConflict; }
    // lib.optionalAttrs (entry ? provenance) { provenance.source = entry.provenance; };
in
{
  # one declaration per entry per user principal handed in.
  # the caller handed this layer every user on the host, and on lumi grandpa
  # took 29 declarations for files only feltfomo receives.
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
