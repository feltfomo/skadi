# _lib/scoped.nix
#
# Apply arbitrary per-class config to ONLY the users/hosts you select.
#
# den already threads { host, user } into every class module, and a home aspect
# resolves at the user scope where BOTH host and user are in context -- so a
# module can always see who and where it is being built for. This turns that
# into a small selector, so per-user / per-host divergence is data, not forked
# files. Any aspect gates a block with `for`; `resolve` filters a whole program
# spec at once, so pkg/files/templates/noctaliaConfig each carry their own
# users/hosts register.
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
  # drop den context. block-only: a miss is {}, so it merges as identity.
  for =
    ctx: sel: value:
    if matches sel ctx then value else { };

  # Filter a whole program spec against ctx, dispatching on each field's shape:
  #  - list (files/templates/imports): drop entries whose users/hosts miss, then
  #    strip those keys off survivors. Bare non-attrset entries (module fns) are
  #    untagged -- kept and passed through untouched.
  #  - non-list field == {}: a `for`-miss, so drop the field (an absent field,
  #    not a {} home.packages can't install). Contract: assumes no field's real
  #    value is a meaningful {} -- true today, pkg is function-typed.
  #  - untagged value/entry is kept -- a selector only ever narrows.
  resolve =
    ctx: spec:
    let
      hit =
        entry:
        matches {
          hosts = entry.hosts or null;
          users = entry.users or null;
        } ctx;
      keepEntry = entry: !(builtins.isAttrs entry) || hit entry;
      stripEntry =
        entry:
        if builtins.isAttrs entry then
          removeAttrs entry [
            "hosts"
            "users"
          ]
        else
          entry;
      present =
        name:
        let
          v = spec.${name};
        in
        builtins.isList v || v != { };
    in
    builtins.listToAttrs (
      map (name: {
        inherit name;
        value =
          let
            v = spec.${name};
          in
          if builtins.isList v then map stripEntry (builtins.filter keepEntry v) else v;
      }) (builtins.filter present (builtins.attrNames spec))
    );
in
{
  inherit matches for resolve;
}
