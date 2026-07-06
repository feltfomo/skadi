# Install-time host composition: build a host with some of its top-level
# aspects removed, for one machine only, WITHOUT editing the host file.
# The canonical nixosConfigurations.<host> is never touched -- this is a
# separate, additive flake.lib output that skadi-install calls only when it
# is handed a drop list. den resolves a host aspect's includes inside its
# pipeline before module eval, so a plain module option can't retro-filter
# them; instead we re-run the host's own standalone resolve chain
# (resolveEntity "host" -> aspects.resolve -> instantiate) against a
# copy of the host whose aspect carries a filtered includes list.
#
# Assumes host-as-root resolution == flake-as-root resolution, which holds
# for pipe-free hosts (no cross-host pipe.collect); a future host that
# collects across the fleet would have to re-derive through the flake root
# rather than this standalone chain.
{
  den,
  lib,
  ...
}:
let
  systems = [ "x86_64-linux" ];

  # The droppable top-level aspect names of a den host record: the .name of
  # every named entry in its aspect's top-level includes. Shared by the
  # mkInstallTarget fail-loud check AND the flake.lib.hostAspects output the
  # installer's interactive menu reads, so the menu, the --drop validation, and
  # the "have: ..." error message can never drift apart. Nameless includes
  # (policy records, bare functions) have no .name and are never listed --
  # `==` on an aspect record throws (they carry functions), so we key on .name.
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

      # Identify aspects by their stable .name -- `==` on the aspect records
      # themselves throws (they carry functions). Nameless entries (policy
      # records, bare functions) have no name and are always kept; only named
      # top-level aspects are droppable.
      aspectName = a: if builtins.isAttrs a then a.name or null else null;
      topLevelNames = topLevelAspectNames h;
      topLevelNameSet = lib.genAttrs topLevelNames (_: true);

      # Fail loud on a drop that matches no top-level aspect (a typo, or a
      # nested aspect): silently keeping everything would build a composition
      # identical to canonical -- e.g. `--drop gpu-nvida` would still ship
      # nvidia. This also pins the top-level-only contract in code.
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

      # Re-run the host's standalone resolve chain with the filtered aspect.
      # Resolve the ENTITY-ROOT from resolveEntity (not the raw host aspect):
      # it carries the host scope handlers, so the entity pipeline --
      # host-to-users then the host-to-hm-users battery -- runs and forwards
      # feltfomo's home-manager + secrets into the imports. den's own host
      # mainModule uses aspects.resolveWithPaths here, but that name isn't on
      # the public den.lib surface (v0.17.0); it is only resolve plus a
      # per-scope path set over the same pipeline, so aspects.resolve yields
      # the identical { imports = ...; } that mainModule consumes.
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
        # den's flake pipeline appends hostPlatform from spec.system; host
        # modules don't set it themselves. mkDefault so a host that does
        # isn't overridden.
        { nixpkgs.hostPlatform = lib.mkDefault h.system; }
      ];
    };
in
{
  flake.lib = lib.genAttrs systems (system: {
    mkInstallTarget = mkInstallTarget system;

    # Introspection for the installer's interactive menu: the droppable
    # top-level aspect names per host. This is the SAME list mkInstallTarget
    # validates --drop against, so a menu built from it can never produce an
    # invalid drop -- the fail-loud assertion only ever guards the explicit
    # --drop path. Lazy per host (mapAttrs); reading one host's entry only
    # forces that host's includes' .names, never a resolved config.
    hostAspects = lib.mapAttrs (_: topLevelAspectNames) den.hosts.${system};
  });
}
