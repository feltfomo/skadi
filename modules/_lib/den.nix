# the den-internals boundary: the ONE file allowed to touch den's guts
# (den.hosts, den.lib.resolveEntity, den.lib.aspects.resolve, h.instantiate,
# h.aspect.includes). everything else -- program, install-target, any future
# den-built framework -- calls these wrappers, never den.lib directly, so a den
# version bump is absorbed here in one place.
{
  den,
  lib,
}:
let
  # an includes entry's aspect name, or null for nameless entries (policies, bare
  # functions). key on .name, never the record itself: `==` on an aspect throws
  # (they carry functions).
  aspectName = a: if builtins.isAttrs a then a.name or null else null;

  # the named top-level aspects of an includes list, in order. nameless entries
  # have no .name and aren't listed (or droppable).
  namedIncludes = includes: builtins.filter (n: n != null) (map aspectName includes);

  # named top-level aspects of a den host, for the install menu and drop
  # validation. lazy per host: forces one host's includes' .names, never a
  # resolved config.
  topLevelAspectNames = h: namedIncludes (h.aspect.includes or [ ]);

  # an includes -> includes transform that removes the named top-level aspects.
  # fails loud on a name matching no top-level aspect (a typo or a nested aspect):
  # silently keeping everything would ship it anyway -- `drop [ "gpu-nvida" ]`
  # would still ship nvidia. host-agnostic; the available-names list is derived
  # from the includes it is handed, so the error is actionable on its own.
  drop =
    names: includes:
    let
      have = namedIncludes includes;
      haveSet = lib.genAttrs have (_: true);
      unmatched = builtins.filter (n: !(haveSet ? ${n})) names;
      quote = n: "\"" + n + "\"";
      checked =
        if unmatched == [ ] then
          names
        else
          throw "den: --drop ${
            lib.concatMapStringsSep ", " quote unmatched
          } matched no top-level aspect (have: ${lib.concatStringsSep ", " have})";
      dropSet = lib.genAttrs checked (_: true);
      keep =
        a:
        let
          n = aspectName a;
        in
        n == null || !(dropSet ? ${n});
    in
    builtins.filter keep includes;

  # build a host standalone with its top-level includes transformed, without
  # editing the host file and without touching the canonical
  # nixosConfigurations.<host>. den resolves a host aspect's includes before
  # module eval, so a plain option can't retro-filter them; instead we re-run the
  # host's own standalone resolve chain (resolveEntity "host" -> aspects.resolve
  # -> instantiate) against a copy of the host whose aspect carries the
  # transformed includes.
  #
  # assumes host-as-root resolution == flake-as-root resolution, which holds for
  # pipe-free hosts; a host that collects across the fleet would have to re-derive
  # through the flake root instead.
  mkTarget =
    {
      system,
      host,
      transformIncludes ? (i: i),
    }:
    let
      h = den.hosts.${system}.${host};
      includes = h.aspect.includes or [ ];
      filteredAspect = h.aspect // {
        # name the host in the trace if the transform throws (e.g. drop's no-match
        # throw). wrapping the transform -- not instantiate -- makes it fire: the
        # throw is forced when this list is forced to WHNF, while instantiate's
        # result is a lazy attrset the throw would escape.
        includes = builtins.addErrorContext "while building install target for host ${host}" (
          transformIncludes includes
        );
      };
      # resolve from the resolveEntity root, not the raw host aspect: it carries
      # the host scope handlers, so the host-to-users then host-to-hm-users
      # batteries run and forward each user's home-manager + secrets into imports.
      resolved = den.lib.resolveEntity "host" {
        host = h // {
          aspect = filteredAspect;
        };
      };
      # imports-only projection. den's mainModule uses aspects.resolveWithPaths;
      # resolve IS that projection minus the per-scope path set -- both are the one
      # fxResolveFull behind a single fx.handle (resolve = its .imports). the
      # dropped pathSetByScope/edgeTrace is introspection the module set never
      # reads, and pipe-free khion/lumi don't read their own projected hasAspect,
      # so resolve yields the identical { imports = ...; }.
      result = den.lib.aspects.resolve h.class resolved;
    in
    h.instantiate {
      modules = [
        { inherit (result) imports; }
        # den's flake pipeline appends hostPlatform from spec.system; a standalone
        # host module set doesn't. mkDefault so a host that sets it isn't overridden.
        { nixpkgs.hostPlatform = lib.mkDefault h.system; }
      ];
    };

  # droppable top-level aspect names per host on a system, for the install menu.
  hostAspects = system: lib.mapAttrs (_: topLevelAspectNames) den.hosts.${system};

  # the ownerships roster, read straight off den's public entity surface: a user
  # is declared inline on its host (den.hosts.<system>.<host>.users), so which
  # users live on which host is already here -- no den internals to reach for.
  # this is the den-backed source for the roster interface; a den-free define.*
  # source produces the same { hosts; users; membership; usersWithUnknownMembership }
  # shape.
  roster =
    system:
    let
      hosts = den.hosts.${system} or { };
      names = builtins.attrNames hosts;
      usersOf = h: builtins.attrNames (hosts.${h}.users or { });
      membership = lib.genAttrs names usersOf;
    in
    {
      hosts = names;
      users = lib.unique (builtins.concatLists (map usersOf names));
      inherit membership;
      # den declares every user on its host, so membership is always known; the
      # unknown set is here only so this shape matches the den-free define.*
      # backend, which can carry users that named no host.
      usersWithUnknownMembership = [ ];
    };
in
{
  inherit
    mkTarget
    drop
    hostAspects
    topLevelAspectNames
    roster
    ;
}
