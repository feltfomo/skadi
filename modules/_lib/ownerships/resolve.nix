# _lib/ownerships/resolve.nix
#
# Public entry. Axis descriptors and relation registrations turn one roster
# into the engine registry and leaf-stage set, so standalone and den-backed
# callers share the same path.
{
  lib,
  descriptors ? null,
  relations ? null,
}:
let
  engine = import ./engine.nix { inherit lib; };
  axes = import ./axes.nix { inherit lib; };
  axisDescriptors = axes.validateDescriptors (
    if descriptors == null then axes.descriptors else descriptors
  );
  relationRegistrations = axes.validateRelations axisDescriptors (
    if relations == null then axes.relations else relations
  );
  mergeLib = import ./merge.nix { inherit lib; };
  rosterLib = import ./roster.nix {
    inherit lib;
    descriptors = axisDescriptors;
  };

  defaultMerge = (mergeLib.mkMerge { }).mergeTracked;

  engineArgsFor =
    roster:
    let
      registry = axes.registryFor axisDescriptors roster;
      relationStages = map (relation: {
        inherit (relation) name;
        view = "leaf";
        run = engine.mkRelationCheck relation;
      }) (axes.relationsFor relationRegistrations roster);
    in
    {
      inherit registry;
      stages = [
        # Alias ambiguity is rejected before satisfiability and relations so a
        # bare alias spanning multiple canonical members fails loud with its own
        # wording rather than surfacing as a generic unknown-name/disjoint error.
        {
          view = "leaf";
          run = axes.aliasValidationCheck;
        }
        {
          view = "leaf";
          run = engine.satisfiableCheck;
        }
      ]
      ++ relationStages
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
