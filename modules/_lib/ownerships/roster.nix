# _lib/ownerships/roster.nix
#
# The roster interface and its den-free backend. A roster is
#   { hosts; users; membership; usersWithUnknownMembership }
# -- host and user name lists, membership as host -> [ user ], and the users
# whose host membership is unknown (declared without any host). Both backends
# produce exactly this shape: the den adapter in ../den.nix reads it off
# den.hosts, and define.* below builds it with no den present, so the engine
# never learns which one it got.
{ lib }:
let
  # define.host / define.user are the standalone declarations. A user names the
  # hosts it lives on; omitting hosts (null) means "unknown", which the
  # membership check treats as could-be-anywhere and lets through. An explicit
  # empty list means "known to live on no host", which stays a real membership
  # failure -- that null-vs-[] split is the whole reason the two forms differ.
  define = {
    host = name: {
      kind = "host";
      inherit name;
    };
    user =
      name:
      {
        hosts ? null,
      }:
      {
        kind = "user";
        inherit name hosts;
      };
  };

  # fold a list of define.* declarations into one roster. hosts come from both
  # explicit define.host calls and any host a user names, so a user can pull its
  # host into existence without a separate declaration.
  toRoster =
    decls:
    let
      users = builtins.filter (d: d.kind == "user") decls;
      hostDecls = builtins.filter (d: d.kind == "host") decls;
      named = builtins.concatMap (u: if u.hosts == null then [ ] else u.hosts) users;
      hostNames = lib.unique (map (d: d.name) hostDecls ++ named);
      usersOn =
        h: map (u: u.name) (builtins.filter (u: u.hosts != null && builtins.elem h u.hosts) users);
    in
    {
      hosts = hostNames;
      users = lib.unique (map (d: d.name) users);
      membership = lib.genAttrs hostNames usersOn;
      usersWithUnknownMembership = map (u: u.name) (builtins.filter (u: u.hosts == null) users);
    };
in
{
  inherit define toRoster;
}
