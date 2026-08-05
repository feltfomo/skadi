# perSystem check that the den adapter and a mirror define.* roster resolve the
# same unit identically, and that the cross-axis membership contradiction fires
# under both backends. This is the only ownerships check that needs den; the den
# read stays inside _lib/den.nix (reached through its roster wrapper here). The
# den-free half of the roster proof lives in checks/ownerships.nix.
{ den, lib, ... }:
let
  resolve = import ../_lib/ownerships/resolve.nix { inherit lib; };
  axes = import ../_lib/ownerships/axes.nix { inherit lib; };
  denAdapter = import ../_lib/den.nix { inherit den lib; };

  inherit (axes) include;
  inherit (resolve) define toRoster resolveWith;

  denRoster = denAdapter.roster;

  # the same fleet declared with no den, to prove the interface -- not just the
  # data -- is backend-independent. den's real fleet lives on one system
  # (x86_64-linux); the mirror federates onto that same system so both backends
  # project identical canonical ids.
  mirror = toRoster [
    (define.host "generic" { system = "x86_64-linux"; })
    (define.host "installer" { system = "x86_64-linux"; })
    (define.host "khion" { system = "x86_64-linux"; })
    (define.host "lumi" { system = "x86_64-linux"; })
    (define.host "vm" { system = "x86_64-linux"; })
    (define.user "owner" { hosts = [ "generic" ]; })
    (define.user "feltfomo" {
      hosts = [
        "khion"
        "lumi"
        "vm"
      ];
    })
    (define.user "grandpa" { hosts = [ "lumi" ]; })
  ];

  # a caller adds host.system additively so the host ctx resolves to its
  # canonical id; a bare host.name alone would default to the standalone system.
  ctx = {
    host = {
      name = "khion";
      system = "x86_64-linux";
    };
    user.name = "feltfomo";
  };

  unit = {
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
  };

  underDen = resolveWith {
    roster = denRoster;
    inherit ctx;
  } unit;
  underDefine = resolveWith {
    roster = mirror;
    inherit ctx;
  } unit;

  # grandpa lives on lumi only, so claiming grandpa inside a khion block is a
  # membership contradiction -- it must fail under both backends.
  crossAxisBad = {
    claim.host = include [ "khion" ];
    children = [
      {
        claim.user = include [ "grandpa" ];
        value.x = 1;
      }
    ];
  };

  throws = x: !(builtins.tryEval (builtins.deepSeq x x)).success;

  # a synthetic second system introduces a bare-name collision. "khion" now maps
  # to two canonical ids. A bare claim must fail loud (never fan out), while the
  # system-qualified canonical id still resolves to exactly one host.
  federated = toRoster [
    (define.host "khion" { system = "x86_64-linux"; })
    (define.host "khion" { system = "aarch64-linux"; })
    (define.user "feltfomo" {
      hosts = [
        "x86_64-linux/khion"
        "aarch64-linux/khion"
      ];
    })
  ];

  fedCtx = {
    host = {
      name = "khion";
      system = "x86_64-linux";
    };
  };

  ambiguousUnit = {
    claim.host = include [ "khion" ];
    value.x = 1;
  };
  qualifiedUnit = {
    claim.host = include [ "x86_64-linux/khion" ];
    value.x = 1;
  };

  collisionVisible =
    federated.aliases.host.khion == [
      "x86_64-linux/khion"
      "aarch64-linux/khion"
    ];
  ambiguityFires = throws (
    resolveWith {
      roster = federated;
      ctx = fedCtx;
    } ambiguousUnit
  );
  qualifiedResolves =
    (resolveWith {
      roster = federated;
      ctx = fedCtx;
    } qualifiedUnit) == {
      x = 1;
    };

  parity =
    underDen == underDefine
    &&
      underDen == {
        packages = [
          "a"
          "b"
        ];
      };
  bothFire =
    throws (
      resolveWith {
        roster = denRoster;
        inherit ctx;
      } crossAxisBad
    )
    && throws (
      resolveWith {
        roster = mirror;
        inherit ctx;
      } crossAxisBad
    );

  federation = collisionVisible && ambiguityFires && qualifiedResolves;

  ok =
    if parity && bothFire && federation then
      true
    else
      throw "ownerships roster parity FAILED (parity=${builtins.toString parity}, cross-axis fires=${builtins.toString bothFire}, federation=${builtins.toString federation})";
in
{
  perSystem =
    { pkgs, ... }:
    {
      checks.ownerships-roster-parity = pkgs.runCommandLocal "ownerships-roster-parity" { } (
        assert ok;
        "touch $out"
      );
    };
}
