# _lib/ownerships/roster.nix
#
# descriptor-driven roster construction and the den-free backend. descriptors
# with no roster projection are skipped, so select-only axes don't invent empty
# roster fields. the den adapter feeds this same projector normalized standalone
# declarations; den itself never leaks into this module.
{
  lib,
  descriptors ? null,
}:
let
  axes = import ./axes.nix { inherit lib; };
  descriptorSet = axes.compileDescriptors (
    if descriptors == null then axes.descriptors else descriptors
  );
  axisDescriptors = descriptorSet.descriptors;
  inherit (descriptorSet) rosterDescriptors;

  mkRoster =
    descriptorSet:
    let
      compiled = axes.compileDescriptors descriptorSet;
      projected = compiled.rosterDescriptors;
      define = builtins.listToAttrs (
        map (descriptor: {
          inherit (descriptor) name;
          value = descriptor.roster.define;
        }) projected
      );
      # a user or host may be declared once per host it lives on -- den's
      # federated stream relies on the projectors unioning those declarations,
      # so repeated canonical ids are the contract here, not a duplicate
      toRoster =
        declarations:
        lib.foldl' (
          roster: descriptor:
          roster
          // descriptor.roster.project {
            inherit declarations roster;
          }
        ) { } projected;
    in
    {
      inherit define toRoster;
    };

  default = mkRoster axisDescriptors;
in
{
  inherit mkRoster rosterDescriptors;
  inherit (default) define toRoster;
}
