# _lib/ownerships/roster-tests.nix
#
# Pure gate for the roster interface and the den-free define.* backend. It
# imports nothing den-related, so a green run here is the proof the standalone
# path resolves with no den present. Covers the cross-axis membership check, the
# null-vs-[] host distinction (unknown degrades, known-none stays a failure),
# and a host-only config on a user-less host staying clear of the check.
{ lib }:
let
  axes = import ./axes.nix { inherit lib; };
  resolve = import ./resolve.nix { inherit lib; };

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
