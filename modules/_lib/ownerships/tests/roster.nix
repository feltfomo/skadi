# _lib/ownerships/tests/roster.nix
#
# pure gate for the roster interface and the den-free define.* backend. it
# imports nothing den-related, so a green run here is the proof the standalone
# path resolves with no den present. covers the cross-axis membership check, the
# null-vs-[] host distinction (unknown degrades, known-none stays a failure),
# and a host-only config on a user-less host staying clear of the check.
{ lib }:
let
  axes = import ../axes.nix { inherit lib; };
  resolve = import ../resolve.nix { inherit lib; };

  inherit (axes) include;
  inherit (resolve) define toRoster resolveWith;

  roster = toRoster [
    (define.host "khion")
    (define.host "lumi")
    (define.host "server")
    (define.user "feltfomo" {
      hosts = [
        "khion"
        "lumi"
      ];
    })
    (define.user "grandpa" { hosts = [ "lumi" ]; })
    (define.user "nomad" { })
    (define.user "ghostless" { hosts = [ ]; })
  ];

  ctxOf = h: u: {
    host.name = h;
    user.name = u;
  };

  throws = x: !(builtins.tryEval (builtins.deepSeq x x)).success;

  r = ctx: unit: resolveWith { inherit roster ctx; } unit;

  cases = [
    {
      name = "define.* resolves a nested host+user unit with no den";
      pass =
        r (ctxOf "khion" "feltfomo") {
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
      name = "cross-axis membership fires: grandpa is not on khion";
      pass = throws (
        r (ctxOf "khion" "grandpa") {
          claim.host = include [ "khion" ];
          children = [
            {
              claim.user = include [ "grandpa" ];
              value.x = 1;
            }
          ];
        }
      );
    }
    {
      name = "unknown-membership user degrades to same-axis-only";
      pass =
        r (ctxOf "khion" "nomad") {
          claim.host = include [ "khion" ];
          children = [
            {
              claim.user = include [ "nomad" ];
              value.x = 1;
            }
          ];
        } == {
          x = 1;
        };
    }
    {
      name = "known-none user still trips membership (null vs [])";
      pass = throws (
        r (ctxOf "khion" "ghostless") {
          claim.host = include [ "khion" ];
          children = [
            {
              claim.user = include [ "ghostless" ];
              value.x = 1;
            }
          ];
        }
      );
    }
    {
      name = "host-only config on a user-less host is not a membership error";
      pass =
        r (ctxOf "server" "feltfomo") {
          claim.host = include [ "server" ];
          value.systemPackages = [ "vim" ];
        } == {
          systemPackages = [ "vim" ];
        };
    }
    {
      name = "distinct canonical user ids select without conflating a shared bare name";
      pass =
        let
          federated = toRoster [
            (define.host "khion")
            (define.host "lumi")
            (define.user "operator" {
              id = "khion/operator";
              hosts = [ "khion" ];
            })
            (define.user "operator" {
              id = "lumi/operator";
              hosts = [ "lumi" ];
            })
          ];
          selected =
            resolveWith
              {
                roster = federated;
                ctx = {
                  host.name = "khion";
                  user = {
                    name = "operator";
                    id = "khion/operator";
                  };
                };
              }
              {
                claim.user = include [ "khion/operator" ];
                value.x = 1;
              };
          ambiguous =
            resolveWith
              {
                roster = federated;
                ctx = {
                  host.name = "khion";
                  user = {
                    name = "operator";
                    id = "khion/operator";
                  };
                };
              }
              {
                claim.user = include [ "operator" ];
                value.x = 1;
              };
        in
        selected == { x = 1; } && throws ambiguous;
    }
    {
      name = "grouped host aliases retain declaration order";
      pass =
        let
          federated = toRoster [
            (define.host "khion" { system = "x86_64-linux"; })
            (define.host "khion" { system = "aarch64-linux"; })
          ];
        in
        federated.aliases.host.khion == [
          "x86_64-linux/khion"
          "aarch64-linux/khion"
        ];
    }
    {
      name = "explicit unknown and ambiguous user host references fail during roster construction";
      pass =
        throws (toRoster [
          (define.host "khion")
          (define.user "operator" { hosts = [ "ghost" ]; })
        ])
        && throws (toRoster [
          (define.host "khion" { system = "x86_64-linux"; })
          (define.host "khion" { system = "aarch64-linux"; })
          (define.user "operator" { hosts = [ "khion" ]; })
        ]);
    }
  ];

  failing = builtins.filter (c: !c.pass) cases;

  ok =
    if failing == [ ] then
      true
    else
      throw "ownerships roster tests FAILED: ${lib.concatMapStringsSep ", " (c: c.name) failing}";
in
{
  inherit cases ok;
}
