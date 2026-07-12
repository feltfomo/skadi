# _lib/ownerships/resolve.nix
#
# Public entry. Turns a roster (from either backend) plus a build ctx into a
# resolver over the engine. This is the single place that feeds roster data into
# the two halves that need it -- the axis registry (satisfiable/select) and the
# cross-axis membership check -- so both the engine and the axes stay unaware of
# where the roster came from. den and standalone define.* flow through here the
# same way.
{ lib }:
let
  engine = import ./engine.nix { inherit lib; };
  axes = import ./axes.nix { inherit lib; };
  mergeLib = import ./merge.nix { inherit lib; };
  rosterLib = import ./roster.nix { inherit lib; };

  defaultMerge = (mergeLib.mkMerge { }).mergeAll;

  # Registry + leaf stages derived from a roster. Both backends produce the
  # same roster shape, so this is where den and standalone define.* become
  # indistinguishable to the engine.
  engineArgsFor = roster: {
    # `when` lives in the shared registry now, not surface-local, so any caller
    # of engineArgsFor gets the predicate axis for free.
    registry = axes.registry { inherit (roster) hosts users; } // {
      when = axes.predicateAxis;
    };
    stages = [
      {
        view = "leaf";
        run = engine.satisfiableCheck;
      }
      {
        view = "leaf";
        run = axes.mkMembershipCheck {
          inherit (roster)
            hosts
            users
            membership
            usersWithUnknownMembership
            ;
        };
      }
    ];
  };

  # Validate a standalone ctx's host/user names (+ their pairing) against the
  # roster before a strict resolve runs -- opt-in, so the core resolver's
  # claim-only contract stays untouched for every existing caller. Reuses the
  # exact registry/leaf stages engineArgsFor already builds for resolveWith: an
  # unknown name collapses through satisfiableCheck's own disjoint-nest
  # message, and an impossible host x user pairing (both names known, but
  # that user doesn't live on that host) collapses through
  # mkMembershipCheck -- neither rule is re-derived here, so there is no
  # second place a roster/membership check can drift out of sync with
  # resolveWith's own. A host-only ctx (user = null) leaves the user axis at
  # its identity (global): satisfiableCheck sees a constant-satisfiable claim
  # and mkMembershipCheck skips a global side by its own existing rule, so
  # "host-only validates host only" falls out of that shared machinery rather
  # than a branch added here.
  validateRosterCtx =
    roster: ctx:
    let
      args = engineArgsFor roster;
      hostName = ctx.host.name;
      userName = if ctx.user == null then null else ctx.user.name;
      claim =
        (engine.topClaim args.registry)
        // {
          host = axes.include [ hostName ];
        }
        // lib.optionalAttrs (userName != null) { user = axes.include [ userName ]; };
      # names the synthetic leaf as a ctx origin rather than an authored unit,
      # so identifyUnit's label branch renders it as one instead of falling
      # through to its unlabeled-unit shape, which is meant for real config.
      label =
        if userName == null then
          "standalone ctx host '${hostName}'"
        else
          "standalone ctx host '${hostName}', user '${userName}'";
      leaf = {
        inherit claim label;
        value = { };
      };
    in
    # engine.check already throws its own rendered diagnostic on a miss and
    # returns the leaf list unchanged otherwise, so forcing it is the whole
    # validation -- there's nothing left to compute from its result.
    builtins.seq (engine.check args.stages args.registry [ leaf ]) ctx;

  resolveWith =
    {
      roster,
      ctx,
      merge ? defaultMerge,
    }:
    unit:
    let
      args = engineArgsFor roster;
    in
    engine.resolve {
      inherit (args) registry stages;
      inherit ctx merge;
    } unit;
in
{
  inherit (rosterLib) define toRoster;
  inherit resolveWith engineArgsFor validateRosterCtx;
}
