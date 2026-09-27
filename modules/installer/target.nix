# installer targets omit selected top-level aspects without changing the host.
{
  denApi,
  lib,
  ...
}:
let
  systems = [ "x86_64-linux" ];
in
{
  flake.lib = lib.genAttrs systems (system: {
    mkInstallTarget =
      {
        host,
        drop ? [ ],
      }:
      denApi.mkTarget {
        inherit system host;
        transformIncludes = denApi.drop drop;
      };

    hostAspects = denApi.hostAspects system;
  });
}
