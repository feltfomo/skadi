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
  krisis = import ./krisis { inherit lib; };

  ownershipAxes = import ./ownerships/axes.nix { inherit lib; };
  ownershipRoster = import ./ownerships/roster.nix {
    inherit lib;
    inherit (ownershipAxes) descriptors;
  };

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
          krisis.throwDiagnostics {
            diagnostics = [
              (krisis.mkDiagnostic {
                severity = "error";
                code = "den/drop-no-match";
                message = "--drop ${lib.concatMapStringsSep ", " quote unmatched} matched no top-level aspect";
                help = "available top-level aspects: ${lib.concatStringsSep ", " have}";
              })
            ];
            formatDiagnostic = krisis.renderPlain;
          };
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
        includes = krisis.withErrorContext "while building install target for host ${host}" (
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

  hostCtxFor = system: host: {
    id = "${system}/${host}";
    name = host;
    inherit system;
  };

  userPrincipalFor = system: host: name: {
    authority = {
      scope = "user";
      identity = name;
    };
    ctx = {
      host = hostCtxFor system host;
      user = { inherit name; };
    };
  };

  # every authority a host's files could belong to, the host itself plus each
  # user den knows about on it. an enumeration of the host, not a statement about
  # which of those users any one aspect reaches.
  # kept for the pure fixtures and furnish-check's principal contexts. a module
  # that declares files takes filePrincipals instead, never this one.
  hostPrincipals =
    { system, host }:
    let
      h = den.hosts.${system}.${host};
      systemPrincipal = {
        authority = {
          scope = "system";
          identity = "${system}/${host}";
        };
        ctx.host = hostCtxFor system host;
      };
    in
    [ systemPrincipal ] ++ map (userPrincipalFor system host) (builtins.attrNames (h.users or { }));

  # the principals a file-owning module declares for, given the user den resolved
  # that module under. a null user is host scope, which owns no home.
  # modules were handed hostPrincipals here instead, and on lumi that gave
  # grandpa 29 declarations for files feltfomo receives.
  filePrincipals =
    {
      system,
      host,
      user ? null,
    }:
    lib.optional (user != null) (userPrincipalFor system host user.name);

  # the host's user names, for an error that has to say who was available.
  hostUserNames = { system, host }: builtins.attrNames (den.hosts.${system}.${host}.users or { });

  # den normalizes its entire entity tree into one federated declaration stream,
  # then the shared descriptor projector produces the public roster shape. Hosts
  # are enumerated across every system in den.hosts (the single source of truth),
  # each carrying its canonical system and whatever dimension data den attaches
  # (read as host.dimensions or {} -- den's own schema is never spelunked). Every
  # den user names the canonical host it came from, so unknown membership stays
  # empty.
  roster =
    let
      systems = builtins.attrNames den.hosts;
      hostDeclsFor =
        system:
        map (
          name:
          ownershipRoster.define.host name {
            inherit system;
            dimensions = den.hosts.${system}.${name}.dimensions or { };
          }
        ) (builtins.attrNames den.hosts.${system});
      userDeclsFor =
        system:
        builtins.concatMap (
          host:
          map (
            name:
            ownershipRoster.define.user name {
              hosts = [ (ownershipAxes.canonicalHostId system host) ];
            }
          ) (builtins.attrNames (den.hosts.${system}.${host}.users or { }))
        ) (builtins.attrNames den.hosts.${system});
      hostDecls = builtins.concatMap hostDeclsFor systems;
      userDecls = builtins.concatMap userDeclsFor systems;
    in
    ownershipRoster.toRoster (hostDecls ++ userDecls);

in
{
  inherit
    mkTarget
    drop
    filePrincipals
    hostAspects
    hostPrincipals
    hostUserNames
    topLevelAspectNames
    roster
    ;
}
