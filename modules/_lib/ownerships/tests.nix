# _lib/ownerships/tests.nix
#
# Pure test gate for the engine. Nothing else consumes the engine yet, so this is
# what proves it works: the three outcomes, a nested resolve, a throwaway third
# axis composing with no core edit, an opt-in merge strategy registering with no
# core edit, and the top identity law per axis. ownerships-check.nix forces `ok`
# under `nix flake check`.
{ lib }:
let
  engine = import ./engine.nix { inherit lib; };
  axes = import ./axes.nix { inherit lib; };
  merge = import ./merge.nix { inherit lib; };

  inherit (axes)
    include
    exclude
    global
    mkSetAxis
    predicateAxis
    ;

  # stubbed roster -- the real den-backed one replaces this later.
  registry = axes.registry {
    hosts = [
      "khion"
      "lumi"
    ];
    users = [
      "feltfomo"
      "grandpa"
    ];
  };

  defaultMerge = (merge.mkMerge { }).mergeAll;

  ctx = {
    host = {
      name = "khion";
    };
    user = {
      name = "feltfomo";
    };
  };

  resolve =
    args: unit:
    engine.resolve (
      {
        inherit registry;
        merge = defaultMerge;
        inherit ctx;
      }
      // args
    ) unit;

  # did forcing this value throw? deepSeq drives the lazy check/merge throws so
  # tryEval actually catches the impossible/conflict cases.
  throws = x: !(builtins.tryEval (builtins.deepSeq x x)).success;

  # the meet law suite runs over a small closed universe, not sampled -- narrow
  # and top touch no roster, so exhaustive is cheap and actually proves the
  # laws instead of hoping a handful of samples happened to cover what matters.
  lawUniverse = [
    "a"
    "b"
    "c"
  ];
  subsetsOf =
    xs:
    if xs == [ ] then
      [ [ ] ]
    else
      let
        rest = subsetsOf (builtins.tail xs);
      in
      rest ++ map (s: [ (builtins.head xs) ] ++ s) rest;
  # every polarity value over the universe: both tags, every subset.
  lawValues = builtins.concatMap (s: [
    (include s)
    (exclude s)
  ]) (subsetsOf lawUniverse);
  # a throwaway axis just to reach `narrow` (== meet) and `top` -- narrow is
  # roster-independent, so which members this axis carries never matters here.
  lawAxis = mkSetAxis {
    key = "law";
    members = lawUniverse;
  };
  # `.set` is a set, not an ordered list -- exclude/exclude narrowing unions it
  # via ++, which can reorder. sort before comparing so the laws test the
  # value, not the union's incidental order.
  canon = v: v // { set = builtins.sort (a: b: a < b) v.set; };
  eqPolarity = a: b: canon a == canon b;

  cases = [
    {
      name = "host+user nest resolves";
      pass =
        resolve { } {
          claim.host = include [
            "khion"
            "lumi"
          ];
          children = [
            { value.packages = [ "a" ]; }
            {
              claim.user = include [ "feltfomo" ];
              value.packages = [ "b" ];
            }
          ];
        } == {
          packages = [
            "a"
            "b"
          ];
        };
    }

    {
      name = "third axis (role) composes with no core change";
      pass =
        engine.resolve
          {
            registry = registry // {
              role = mkSetAxis {
                key = "role";
                members = [
                  "laptop"
                  "desktop"
                ];
              };
            };
            merge = defaultMerge;
            ctx = ctx // {
              role = {
                name = "desktop";
              };
            };
          }
          {
            claim.role = include [ "desktop" ];
            value.enable = true;
          } == {
          enable = true;
        };
    }

    {
      name = "disjoint nest -> impossible";
      pass = throws (
        resolve { } {
          claim.host = include [ "khion" ];
          children = [
            {
              claim.host = include [ "lumi" ];
              value.x = 1;
            }
          ];
        }
      );
    }

    {
      name = "nested blocks merge";
      pass =
        resolve { } {
          children = [
            {
              value = {
                a.b = [ 1 ];
                c = "keep";
              };
            }
            {
              value = {
                a.b = [ 2 ];
                d = "also";
              };
            }
          ];
        } == {
          a.b = [
            1
            2
          ];
          c = "keep";
          d = "also";
        };
    }

    {
      name = "scalar clash -> conflict";
      pass = throws (
        resolve { } {
          children = [
            { value.port = 80; }
            { value.port = 443; }
          ];
        }
      );
    }

    {
      name = "inactive leaf drops silently";
      pass =
        resolve { } {
          children = [
            { value.shared = true; }
            {
              claim.host = include [ "lumi" ];
              value.lumiOnly = true;
            }
          ];
        } == {
          shared = true;
        };
    }

    {
      name = "dedup-union opt-in strategy registers";
      pass =
        engine.resolve
          {
            inherit registry ctx;
            merge =
              (merge.mkMerge {
                listStrategyFor = path: if path == "tags" then "dedup-union" else "ordered-concat";
              }).mergeAll;
          }
          {
            children = [
              {
                value = {
                  tags = [
                    "x"
                    "y"
                  ];
                  log = [ 1 ];
                };
              }
              {
                value = {
                  tags = [
                    "y"
                    "z"
                  ];
                  log = [ 2 ];
                };
              }
            ];
          } == {
          tags = [
            "x"
            "y"
            "z"
          ];
          log = [
            1
            2
          ];
        };
    }

    {
      name = "top identity law per axis";
      pass =
        let
          samples = [
            (include [ "khion" ])
            (exclude [ "lumi" ])
            global
            (include [ ])
          ];
          law =
            axis:
            # a set axis's top is its global identity, so isTop must accept it;
            # the narrow identity law then holds for every sample around it.
            axis.isTop axis.top
            && lib.all (v: axis.narrow axis.top v == v && axis.narrow v axis.top == v) samples;
        in
        lib.all law [
          registry.host
          registry.user
          (mkSetAxis {
            key = "role";
            members = [ "laptop" ];
          })
        ];
    }

    {
      name = "polarity meet: identity law, exhaustive over {a,b,c}";
      pass = lib.all (
        v: eqPolarity (lawAxis.narrow lawAxis.top v) v && eqPolarity (lawAxis.narrow v lawAxis.top) v
      ) lawValues;
    }

    {
      name = "polarity meet: commutativity law, exhaustive over {a,b,c}";
      pass = lib.all (
        a: lib.all (b: eqPolarity (lawAxis.narrow a b) (lawAxis.narrow b a)) lawValues
      ) lawValues;
    }

    {
      name = "polarity meet: idempotence law, exhaustive over {a,b,c}";
      pass = lib.all (v: eqPolarity (lawAxis.narrow v v) v) lawValues;
    }

    {
      name = "polarity meet: associativity law, exhaustive over {a,b,c}";
      pass = lib.all (
        a:
        lib.all (
          b:
          lib.all (
            c: eqPolarity (lawAxis.narrow (lawAxis.narrow a b) c) (lawAxis.narrow a (lawAxis.narrow b c))
          ) lawValues
        ) lawValues
      ) lawValues;
    }

    {
      name = "ctx missing a set axis's key still throws when a claim narrows on it";
      pass = throws (
        engine.resolve
          {
            inherit registry;
            merge = defaultMerge;
            ctx = {
              host = {
                name = "khion";
              };
            };
          }
          {
            claim.user = include [ "feltfomo" ];
            value.x = 1;
          }
      );
    }

    {
      name = "untagged claim tolerates a null-or-absent ctx entity";
      pass =
        engine.resolve {
          inherit registry;
          merge = defaultMerge;
          # exactly what a bare program.nix caller passes -- keys present, null.
          ctx = {
            host = null;
            user = null;
          };
        } { value.x = 1; } == {
          x = 1;
        };
    }

    {
      name = "predicate axis needs no ctx entity of its own";
      pass =
        engine.resolve
          {
            registry = registry // {
              when = predicateAxis;
            };
            merge = defaultMerge;
            inherit ctx;
          }
          {
            claim.when = c: c.host.name == "khion";
            value.enable = true;
          } == {
          enable = true;
        };
    }

    {
      name = "host-narrowed claim resolves with the user entity explicitly null";
      pass =
        engine.resolve
          {
            inherit registry;
            merge = defaultMerge;
            # a host-only build: real host, user absent from scope. the user axis
            # stays global for this claim, so assertCtx never demands it and
            # select never reads it -- the null-user tolerance the system binding
            # rides on.
            ctx = {
              host = {
                name = "khion";
              };
              user = null;
            };
          }
          {
            claim.host = include [ "khion" ];
            value.x = 1;
          } == {
          x = 1;
        };
    }
  ];

  failing = builtins.filter (c: !c.pass) cases;

  ok =
    if failing == [ ] then
      true
    else
      throw "ownerships tests FAILED: ${lib.concatMapStringsSep ", " (c: c.name) failing}";
in
{
  inherit cases ok;
}
