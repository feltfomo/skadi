# install-time host composition: build a host with some top-level aspects removed,
# for one machine only, without editing the host file. the canonical
# nixosConfigurations.<host> is never touched. den resolves a host aspect's
# includes before module eval, so a plain option can't retro-filter them; instead
# we re-run the host's standalone resolve chain
# (resolveEntity "host" -> aspects.resolve -> instantiate) against a copy of the
# host whose aspect carries a filtered includes list.
#
# assumes host-as-root resolution == flake-as-root resolution, which holds for
# pipe-free hosts; a host that collects across the fleet would have to re-derive
# through the flake root instead.
{
  den,
  lib,
  ...
}:
let
  systems = [ "x86_64-linux" ];

  # droppable top-level aspect names of a den host: the .name of every named entry
  # in its aspect's top-level includes. shared by the mkInstallTarget check and the
  # flake.lib.hostAspects output the menu reads, so menu, validation and error
  # message can't drift. nameless includes have no .name and are never listed --
  # `==` on an aspect record throws (they carry functions), so key on .name.
  topLevelAspectNames =
    h:
    let
      includes = h.aspect.includes or [ ];
      aspectName = a: if builtins.isAttrs a then a.name or null else null;
    in
    builtins.filter (n: n != null) (map aspectName includes);

  mkInstallTarget =
    system:
    {
      host,
      drop ? [ ],
    }:
    let
      h = den.hosts.${system}.${host};
      includes = h.aspect.includes or [ ];

      # identify aspects by .name; nameless entries (policies, bare functions) are
      # always kept, only named top-level aspects are droppable.
      aspectName = a: if builtins.isAttrs a then a.name or null else null;
      topLevelNames = topLevelAspectNames h;
      topLevelNameSet = lib.genAttrs topLevelNames (_: true);

      # fail loud on a drop matching no top-level aspect (a typo or nested aspect):
      # silently keeping everything would ship it anyway -- `--drop gpu-nvida` would
      # still ship nvidia.
      unmatched = builtins.filter (n: !(topLevelNameSet ? ${n})) drop;
      quote = n: "\"" + n + "\"";
      checkedDrop =
        if unmatched == [ ] then
          drop
        else
          throw "den: --drop ${
            lib.concatMapStringsSep ", " quote unmatched
          } matched no top-level aspect on host ${host} (have: ${lib.concatStringsSep ", " topLevelNames})";

      dropSet = lib.genAttrs checkedDrop (_: true);
      keep =
        a:
        let
          n = aspectName a;
        in
        n == null || !(dropSet ? ${n});
      filteredAspect = h.aspect // {
        includes = builtins.filter keep includes;
      };

      # re-run the host's standalone resolve chain with the filtered aspect. resolve
      # the entity-root from resolveEntity, not the raw host aspect: it carries the
      # host scope handlers, so host-to-users then the host-to-hm-users battery run
      # and forward feltfomo's home-manager + secrets into the imports. den's
      # mainModule uses aspects.resolveWithPaths here but that isn't on the public
      # den.lib surface (v0.17.0); it's just resolve plus a per-scope path set, so
      # aspects.resolve yields the identical { imports = ...; }.
      resolved = den.lib.resolveEntity "host" {
        host = h // {
          aspect = filteredAspect;
        };
      };
      result = den.lib.aspects.resolve h.class resolved;
    in
    h.instantiate {
      modules = [
        { inherit (result) imports; }
        # den's flake pipeline appends hostPlatform from spec.system; host modules
        # don't set it. mkDefault so a host that does isn't overridden.
        { nixpkgs.hostPlatform = lib.mkDefault h.system; }
      ];
    };
in
{
  flake.lib = lib.genAttrs systems (system: {
    mkInstallTarget = mkInstallTarget system;

    # droppable top-level aspect names per host for the menu -- the same list
    # mkInstallTarget validates --drop against, so a menu built from it can't
    # produce an invalid drop. lazy per host: reading one entry only forces that
    # host's includes' .names, never a resolved config.
    hostAspects = lib.mapAttrs (_: topLevelAspectNames) den.hosts.${system};
  });
}
