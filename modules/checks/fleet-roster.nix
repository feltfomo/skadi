# lexicon proves the engine; this proves skadi's own fleet resolves the same read
# through den as hand-declared facade only
{
  ownerships,
  roster,
  ...
}:
let
  inherit (ownerships) define toRoster mkResolve;

  # same fleet without den, on the same system so both project identical ids
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

  # host.system keeps this on the canonical id instead of the standalone one.
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

  # grandpa is lumi-only, so this must fail under both backends.
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

  # two systems make bare khion claims ambiguous while qualified claims resolve.
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
  perSystem = { pkgs, ... }: {
    checks.fleet-roster-parity = pkgs.runCommandLocal "fleet-roster-parity" { } (
      assert ok;
      "touch $out"
    );
  };
}
