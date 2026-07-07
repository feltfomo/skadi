# _lib/scoped.nix
#
# Apply arbitrary per-class config to ONLY the users/hosts you select.
#
# den already threads { host, user } into every class module, and a home aspect
# resolves at the user scope where BOTH host and user are in context -- so a
# module can always see who and where it is being built for. This turns that
# into a small selector, so per-user / per-host divergence is data, not forked
# files. Any aspect gates a block with `for`; program.nix reuses `matches` to
# filter each file by the `users` / `hosts` register declared on it.
_:
let
  # selector -> ctx -> bool. A null field does not constrain; the fields that
  # are set must all hold (AND). Names match the den entity `name` -- the attr
  # the host/user is declared under (e.g. "khion", "feltfomo").
  matches =
    {
      hosts ? null,
      users ? null,
      when ? null,
    }:
    {
      host ? null,
      user ? null,
      ...
    }@ctx:
    let
      hostOk = hosts == null || (host != null && builtins.elem host.name hosts);
      userOk = users == null || (user != null && builtins.elem user.name users);
      whenOk = when == null || when ctx;
    in
    hostOk && userOk && whenOk;

  # value stays inline so its body reads host/user by closure -- imports would
  # drop den context. block-only: a miss is {}, so scalar fields wait for SP2.
  for =
    ctx: sel: value:
    if matches sel ctx then value else { };
in
{
  inherit matches for;
}
