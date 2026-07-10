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
          law = axis: lib.all (v: axis.narrow axis.top v == v && axis.narrow v axis.top == v) samples;
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
