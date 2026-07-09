# install-time host composition: build a host with some top-level aspects removed,
# for one machine only, without editing the host file. the canonical
# nixosConfigurations.<host> is never touched. the den-internals work (the
# filtered standalone resolve + instantiate) lives in _lib/den.nix; this wires the
# --drop menu to that boundary and is otherwise a thin caller.
{
  den,
  lib,
  ...
}:
let
  systems = [ "x86_64-linux" ];
  denApi = import ./_lib/den.nix { inherit den lib; };
in
{
  flake.lib = lib.genAttrs systems (system: {
    # build <host> with the named top-level aspects dropped. denApi.drop is the
    # includes -> includes transform (and the loud no-match check); mkTarget
    # re-runs the host's standalone resolve chain against the filtered includes.
    mkInstallTarget =
      {
        host,
        drop ? [ ],
      }:
      denApi.mkTarget {
        inherit system host;
        transformIncludes = denApi.drop drop;
      };

    # droppable top-level aspect names per host for the menu -- the same names
    # denApi.drop validates --drop against, so a menu built from it can't produce
    # an invalid drop.
    hostAspects = denApi.hostAspects system;
  });
}
