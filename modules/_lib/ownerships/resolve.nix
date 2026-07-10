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

  # registry + checks derived from a roster. both backends produce the same
  # roster shape, so this is where den and standalone define.* become
  # indistinguishable to the engine.
  engineArgsFor = roster: {
    # `when` lives in the shared registry now, not surface-local, so any caller
    # of engineArgsFor gets the predicate axis for free.
    registry = axes.registry { inherit (roster) hosts users; } // {
      when = axes.predicateAxis;
    };
    checks = [
      engine.satisfiableCheck
      (axes.mkMembershipCheck {
        inherit (roster)
          hosts
          users
          membership
          usersWithUnknownMembership
          ;
      })
    ];
  };

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
      inherit (args) registry checks;
      inherit ctx merge;
    } unit;
in
{
  inherit (rosterLib) define toRoster;
  inherit resolveWith engineArgsFor;
}
