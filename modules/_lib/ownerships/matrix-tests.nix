# _lib/ownerships/matrix-tests.nix
#
# Fleet audit proofs: parity with real resolution, engine-defined dead claims,
# open-roster uncertainty, separate user/system contexts, and report laziness.
{ lib }:
let
  surface = import ./surface.nix { inherit lib; };
  inherit (surface)
    define
    toRoster
    mkResolve
    mkResolveSystem
    mkResolveMatrix
    mkResolveSystemMatrix
    ;

  roster = toRoster [
    (define.host "khion")
    (define.host "lumi")
    (define.user "feltfomo" {
      hosts = [
        "khion"
        "lumi"
      ];
    })
    (define.user "grandpa" { hosts = [ "lumi" ]; })
    (define.user "nomad" { })
  ];

  resolve = mkResolve roster;
  resolveSystem = mkResolveSystem roster;
  resolveMatrix = mkResolveMatrix roster;
  resolveSystemMatrix = mkResolveSystemMatrix roster;

  contexts = {
    khionFeltfomo = {
      host.name = "khion";
      user.name = "feltfomo";
    };
    lumiFeltfomo = {
      host.name = "lumi";
      user.name = "feltfomo";
    };
    lumiGrandpa = {
      host.name = "lumi";
      user.name = "grandpa";
    };
  };

  poisonDerivation = {
    type = "derivation";
    name = "poison-pkg";
    drvPath = throw "matrix forced a derivation";
    outPath = throw "matrix forced a derivation";
  };
  poisonSecret.token = throw "matrix forced a secret";

  units = [
    {
      label = "global";
      shared = true;
      pkg = poisonDerivation;
      secret = poisonSecret;
    }
    {
      label = "khion-only";
      hosts = [ "khion" ];
      khion = true;
    }
    {
      label = "grandpa-only";
      users = [ "grandpa" ];
      grandpa = true;
    }
    {
      label = "runtime-only";
      when = _ctx: false;
      runtime = true;
    }
    {
      label = "dead-host";
      hosts = [ "ghost" ];
      dead = true;
    }
    {
      label = "impossible-pair";
      hosts = [ "khion" ];
      users = [ "grandpa" ];
      impossiblePair = true;
    }
    {
      label = "unknown-only";
      users = [ "nomad" ];
      unknown = true;
    }
  ];

  matrix = resolveMatrix { inherit units; };

  agreementUnits = [
    {
      label = "global";
      shared = true;
    }
    {
      label = "khion-only";
      hosts = [ "khion" ];
      khion = true;
    }
    {
      label = "grandpa-only";
      users = [ "grandpa" ];
      grandpa = true;
    }
  ];
  agreementMatrix = resolveMatrix { units = agreementUnits; };

  systemUnits = [
    {
      label = "system-global";
      system = true;
    }
    {
      label = "system-khion";
      hosts = [ "khion" ];
      khionSystem = true;
    }
  ];
  systemMatrix = resolveSystemMatrix { units = systemUnits; };

  throws = value: !(builtins.tryEval (builtins.deepSeq value value)).success;
  identities = entries: map (entry: entry.identity) entries;
  inactiveNamed =
    name:
    builtins.head (
      builtins.filter (entry: entry.identity == "unit '${name}'") matrix.neverSelectedInModeledContexts
    );

  cases = [
    {
      name = "user matrix survivors agree with real resolve in every valid context";
      pass =
        agreementMatrix.byContext."khion/feltfomo".survivors == [
          "leaf-0"
          "leaf-1"
        ]
        && agreementMatrix.byContext."lumi/feltfomo".survivors == [ "leaf-0" ]
        &&
          agreementMatrix.byContext."lumi/grandpa".survivors == [
            "leaf-0"
            "leaf-2"
          ]
        &&
          resolve agreementUnits contexts.khionFeltfomo == {
            shared = true;
            khion = true;
          }
        && resolve agreementUnits contexts.lumiFeltfomo == { shared = true; }
        &&
          resolve agreementUnits contexts.lumiGrandpa == {
            shared = true;
            grandpa = true;
          };
    }
    {
      name = "dead uses the engine impossibility diagnostics for axis and relation failures";
      pass =
        identities matrix.dead == [
          "unit 'dead-host'"
          "unit 'impossible-pair'"
        ]
        &&
          (builtins.elemAt matrix.dead 0).reasons == [
            {
              kind = "impossible";
              axis = "host";
              reason = "axis 'host' claim can never be satisfied (disjoint nest or unknown name)";
            }
          ]
        &&
          (builtins.elemAt matrix.dead 1).reasons == [
            {
              kind = "impossible";
              axes = [
                "host"
                "user"
              ];
              reason = "no user in { grandpa } lives on any host in { khion } -- this host/user co-ownership can never apply";
            }
          ];
    }
    {
      name = "cross-axis dead matches the real resolver's impossible outcome";
      pass = throws (
        resolve [
          {
            hosts = [ "khion" ];
            users = [ "grandpa" ];
            impossiblePair = true;
          }
        ] contexts.khionFeltfomo
      );
    }
    {
      name = "unknown membership is excluded from rows and surfaced as indeterminate";
      pass =
        builtins.attrNames matrix.byContext == [
          "khion/feltfomo"
          "lumi/feltfomo"
          "lumi/grandpa"
        ]
        && matrix.indeterminate.unknownMembershipUsers == [ "nomad" ]
        && identities matrix.indeterminate.units == [ "unit 'unknown-only'" ]
        && !(builtins.elem "unit 'unknown-only'" (identities matrix.neverSelectedInModeledContexts))
        && !(builtins.elem "unit 'unknown-only'" (identities matrix.dead));
    }
    {
      name = "when misses are observationally inactive, never dead";
      pass =
        !(builtins.elem "unit 'runtime-only'" (identities matrix.dead))
        && !(builtins.elem "unit 'runtime-only'" (identities matrix.indeterminate.units))
        &&
          (inactiveNamed "runtime-only").rejections == {
            "khion/feltfomo" = [ "when" ];
            "lumi/feltfomo" = [ "when" ];
            "lumi/grandpa" = [ "when" ];
          };
    }
    {
      name = "stable keys distinguish unit identity from snapshot position";
      pass =
        matrix.units.leaf-0.identity == "unit 'global'"
        && matrix.units.leaf-4.identity == "unit 'dead-host'"
        && matrix.units.leaf-6.identity == "unit 'unknown-only'";
    }
    {
      name = "unit and top-level pre-merge coverage are pinned";
      pass =
        matrix.coverage.units.leaf-0 == [
          "khion/feltfomo"
          "lumi/feltfomo"
          "lumi/grandpa"
        ]
        && matrix.coverage.units.leaf-1 == [ "khion/feltfomo" ]
        && matrix.coverage.units.leaf-2 == [ "lumi/grandpa" ]
        && matrix.coverage.units.leaf-4 == [ ]
        && matrix.coverage.preMerge.meaning == "top-level paths offered by surviving leaves before merge"
        && matrix.coverage.preMerge.paths.khion == [ "khion/feltfomo" ]
        && matrix.coverage.preMerge.paths.grandpa == [ "lumi/grandpa" ];
    }
    {
      name = "host diffs include unit keys and top-level pre-merge paths";
      pass =
        matrix.hostDiffs."khion -> lumi" == {
          units = {
            leftOnly = [ "leaf-1" ];
            rightOnly = [ "leaf-2" ];
          };
          preMergePaths = {
            leftOnly = [ "khion" ];
            rightOnly = [ "grandpa" ];
          };
        };
    }
    {
      name = "the full report never forces surviving package or secret values";
      pass = (builtins.tryEval (builtins.deepSeq matrix matrix)).success;
    }
    {
      name = "system matrix agrees with host-only resolution and has its own row shape";
      pass =
        systemMatrix.byContext.khion.survivors == [
          "leaf-0"
          "leaf-1"
        ]
        && systemMatrix.byContext.lumi.survivors == [ "leaf-0" ]
        && !(systemMatrix.byContext.khion ? userName)
        &&
          resolveSystem systemUnits { host.name = "khion"; } == {
            system = true;
            khionSystem = true;
          }
        && resolveSystem systemUnits { host.name = "lumi"; } == { system = true; }
        &&
          systemMatrix.hostDiffs."khion -> lumi" == {
            units = {
              leftOnly = [ "leaf-1" ];
              rightOnly = [ ];
            };
            preMergePaths = {
              leftOnly = [ "khionSystem" ];
              rightOnly = [ ];
            };
          };
    }
    {
      name = "system matrix keeps the recursive user-claim guard";
      pass = throws (resolveSystemMatrix {
        units = [
          {
            children = [
              {
                users = [ "feltfomo" ];
                invalid = true;
              }
            ];
          }
        ];
      });
    }
  ];

  failing = builtins.filter (case: !case.pass) cases;
  ok =
    if failing == [ ] then
      true
    else
      throw "ownerships matrix tests FAILED: ${lib.concatMapStringsSep ", " (case: case.name) failing}";
in
{
  inherit
    cases
    matrix
    systemMatrix
    ok
    ;
}
