# perSystem check that the den adapter and a mirror define.* roster resolve the
# same unit identically, and that the cross-axis membership contradiction fires
# under both backends. This is the only ownerships check that needs den; the den
# read stays inside _lib/den.nix (reached through its roster wrapper here). The
# den-free half of the roster proof lives in ownerships-check.nix.
{ den, lib, ... }:
let
  resolve = import ./_lib/ownerships/resolve.nix { inherit lib; };
  axes = import ./_lib/ownerships/axes.nix { inherit lib; };
  denAdapter = import ./_lib/den.nix { inherit den lib; };

  inherit (axes) include;
  inherit (resolve) define toRoster resolveWith;

  denRoster = denAdapter.roster "x86_64-linux";

  # the same fleet declared with no den, to prove the interface -- not just the
  # data -- is backend-independent.
  mirror = toRoster [
    (define.host "generic")
    (define.host "installer")
    (define.host "khion")
    (define.host "lumi")
    (define.host "vm")
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

  ctx = {
    host.name = "khion";
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

  ok =
    if parity && bothFire then
      true
    else
      throw "ownerships roster parity FAILED (parity=${builtins.toString parity}, cross-axis fires=${builtins.toString bothFire})";
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
