# _lib/ownerships/resolve.nix
#
# Public entry. Axis descriptors turn one roster into the engine registry and
# leaf-stage set, so standalone and den-backed callers share the same path.
{
  lib,
  descriptors ? null,
}:
let
  engine = import ./engine.nix { inherit lib; };
  axes = import ./axes.nix { inherit lib; };
  axisDescriptors = if descriptors == null then axes.descriptors else descriptors;
  mergeLib = import ./merge.nix { inherit lib; };
  rosterLib = import ./roster.nix {
    inherit lib;
    descriptors = axisDescriptors;
  };

  defaultMerge = (mergeLib.mkMerge { }).mergeTracked;

  engineArgsFor = roster: {
    registry = axes.registryFor axisDescriptors roster;
    stages = [
      {
        view = "leaf";
        run = engine.satisfiableCheck;
      }
    ]
    ++ axes.leafStagesFor axisDescriptors roster;
  };

  validateRosterCtx =
    roster: ctx:
    let
      args = engineArgsFor roster;
      claim = (engine.topClaim args.registry) // axes.ctxClaimFor axisDescriptors ctx;
      label = "standalone ctx ${axes.ctxLabelFor axisDescriptors ctx}";
      leaf = {
        inherit claim label;
        value = { };
      };
    in
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
  inherit (rosterLib) define toRoster mkRoster;
  inherit resolveWith engineArgsFor validateRosterCtx;
}
