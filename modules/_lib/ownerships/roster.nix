# _lib/ownerships/roster.nix
#
# Descriptor-driven roster construction and the den-free backend. Descriptors
# with no roster projection are skipped, so select-only axes don't invent empty
# roster fields. The den adapter feeds this same projector normalized standalone
# declarations; den itself never leaks into this module.
{
  lib,
  descriptors ? null,
}:
let
  axes = import ./axes.nix { inherit lib; };
  axisDescriptors = axes.validateDescriptors (
    if descriptors == null then axes.descriptors else descriptors
  );

  rosterDescriptors = builtins.filter (descriptor: descriptor.roster != null) axisDescriptors;

  mkRoster =
    descriptorSet:
    let
      checked = axes.validateDescriptors descriptorSet;
      projected = builtins.filter (descriptor: descriptor.roster != null) checked;
      define = builtins.listToAttrs (
        map (descriptor: {
          inherit (descriptor) name;
          value = descriptor.roster.define;
        }) projected
      );
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
