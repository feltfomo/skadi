# _lib/scoped.nix
#
# Apply arbitrary per-class config to ONLY the users/hosts you select.
#
# den already threads { host, user } into every class module, and a home aspect
# resolves at the user scope where BOTH host and user are in context -- so a
# module can always see who and where it is being built for. This turns that
# into a small selector, so per-user / per-host divergence is data, not forked
# files. Any aspect/class can use `scope`; program.nix reuses `matches` to filter
# each file by the `users` / `hosts` register declared on it.
{ lib }:
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

  # Build guarded class modules that emit `body` only where the selector holds.
  # `body` is a normal class module (an attrset, or `args: attrset`); when the
  # selector misses it is simply not imported. Returns only the classes you
  # provided -- spread the result into a den aspect or drop it in an `includes`.
  #
  # Why the guard forwards via `imports` instead of calling `body` itself:
  # den pre-applies the context args a function NAMES (host/user/home) and treats
  # the function's RETURN VALUE as the class module -- module-system args like
  # `pkgs`/`config`/`lib` are supplied by the class's own module system to the
  # modules it evaluates, NOT spliced into a context-taking wrapper's args. So a
  # wrapper that names only host/user and then calls `body args` hands `body` a
  # context-only arg set with no `pkgs` (the bug this replaces). Instead we RETURN
  # a module that conditionally imports `body`: the class module system then hands
  # `body` the full arg set exactly as if it had been written inline. host/user
  # come from the wrapper's own context closure (den provides them), and the
  # selector resolves from context before module eval, so it is safe to decide an
  # `imports` list with it (no config-dependency / no infinite recursion).
  scope =
    {
      hosts ? null,
      users ? null,
      when ? null,
      nixos ? null,
      homeManager ? null,
      hjem ? null,
    }:
    let
      m = matches { inherit hosts users when; };
      guard =
        body:
        (
          {
            host ? null,
            user ? null,
            ...
          }:
          {
            imports = lib.optionals (m { inherit host user; }) [ body ];
          }
        );
    in
    lib.filterAttrs (_: v: v != null) {
      nixos = if nixos != null then guard nixos else null;
      homeManager = if homeManager != null then guard homeManager else null;
      hjem = if hjem != null then guard hjem else null;
    };
in
{
  inherit matches scope;
}
