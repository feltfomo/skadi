# the one ownerships check skadi keeps, because it is not a check on ownerships.
# the engine, the roster backend and the membership rules are lexicon's to prove,
# and lexicon proves them against a synthetic fleet. what is under test here is
# THIS fleet: skadi's five hosts and three users, read through den, resolving the
# same as the same fleet hand-declared. that data lives here, so this check does
# too -- lexicon has no hosts to read.
#
# it goes through the public facade only. reaching into the engine would make
# this a test of lexicon's internals, which is the thing extraction was for.
{
  ownerships,
  roster,
  ...
}:
let
  inherit (ownerships) define toRoster mkResolve;

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
    hosts = [
      "khion"
      "lumi"
    ];
    children = [
      { packages = [ "a" ]; }
      {
        users = [ "feltfomo" ];
        packages = [ "b" ];
      }
    ];
  };

  underDen = mkResolve roster [ unit ] ctx;
  underDefine = mkResolve mirror [ unit ] ctx;

  # grandpa lives on lumi only, so claiming grandpa inside a khion block is a
  # membership contradiction -- it must fail under both backends.
  crossAxisBad = {
    hosts = [ "khion" ];
    children = [
      {
        users = [ "grandpa" ];
        x = 1;
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
    user.name = "feltfomo";
  };

  ambiguousUnit = {
    hosts = [ "khion" ];
    x = 1;
  };
  qualifiedUnit = {
    hosts = [ "x86_64-linux/khion" ];
    x = 1;
  };

  collisionVisible =
    federated.aliases.host.khion == [
      "x86_64-linux/khion"
      "aarch64-linux/khion"
    ];
  ambiguityFires = throws (mkResolve federated [ ambiguousUnit ] fedCtx);
  qualifiedResolves =
    mkResolve federated [ qualifiedUnit ] fedCtx == {
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
    throws (mkResolve roster [ crossAxisBad ] ctx) && throws (mkResolve mirror [ crossAxisBad ] ctx);

  federation = collisionVisible && ambiguityFires && qualifiedResolves;

  ok =
    if parity && bothFire && federation then
      true
    else
      throw "skadi fleet roster parity FAILED (parity=${builtins.toString parity}, cross-axis fires=${builtins.toString bothFire}, federation=${builtins.toString federation})";
in
{
  perSystem =
    { pkgs, ... }:
    {
      checks.fleet-roster-parity = pkgs.runCommandLocal "fleet-roster-parity" { } (
        assert ok;
        "touch $out"
      );
    };
}
