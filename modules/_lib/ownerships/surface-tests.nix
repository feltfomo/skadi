# _lib/ownerships/surface-tests.nix
#
# Proof for the authoring surface: throwaway aspects written the way a real one
# would be, resolved against a small fleet. `results` is the resolved output per
# claim kind, kept plain so it can be eyeballed with `nix eval`; `ok` asserts
# each and is what a flake check forces. Nothing den-related is imported, so a
# green run also proves the surface resolves standalone.
{ lib }:
let
  surface = import ./surface.nix { inherit lib; };
  inherit (surface) define toRoster mkResolve;

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
  ];

  resolve = mkResolve roster;

  # khion, as feltfomo, on an nvidia box -- enough to drive the host/user set
  # claims and a `when` predicate that reads a freeform host attribute.
  ctx = {
    host = {
      name = "khion";
      gpu = "nvidia";
    };
    user = {
      name = "feltfomo";
    };
  };
  # same user, other machine, no nvidia -- the miss side of every claim.
  ctxLumi = {
    host = {
      name = "lumi";
      gpu = "amd";
    };
    user = {
      name = "feltfomo";
    };
  };
  # grandpa building on the host he actually lives on -- for the exclude-self case.
  ctxGrandpa = {
    host = {
      name = "lumi";
      gpu = "amd";
    };
    user = {
      name = "grandpa";
    };
  };

  run = c: units: resolve units c;

  results = {
    global = run ctx [ { pkg = "everyone"; } ];

    hostHit = run ctx [
      {
        hosts = [ "khion" ];
        pkg = "khion-only";
      }
    ];
    hostMiss = run ctxLumi [
      {
        hosts = [ "khion" ];
        pkg = "khion-only";
      }
    ];

    userHit = run ctx [
      {
        users = [ "feltfomo" ];
        pkg = "feltfomo-only";
      }
    ];
    userMiss = run ctx [
      {
        users = [ "grandpa" ];
        pkg = "grandpa-only";
      }
    ];

    exceptHostActive = run ctx [
      {
        exceptHosts = [ "lumi" ];
        pkg = "not-lumi";
      }
    ];
    exceptHostInactive = run ctxLumi [
      {
        exceptHosts = [ "lumi" ];
        pkg = "not-lumi";
      }
    ];

    exceptUserActive = run ctx [
      {
        exceptUsers = [ "grandpa" ];
        pkg = "not-grandpa";
      }
    ];
    exceptUserInactive = run ctxGrandpa [
      {
        exceptUsers = [ "grandpa" ];
        pkg = "not-grandpa";
      }
    ];

    whenHit = run ctx [
      {
        when = { host, ... }: host.gpu == "nvidia";
        pkg = "nvidia-only";
      }
    ];
    whenMiss = run ctxLumi [
      {
        when = { host, ... }: host.gpu == "nvidia";
        pkg = "nvidia-only";
      }
    ];

    # a block owned by two hosts, narrowed inside to a user and to one host, with
    # an option-path unit alongside -- proves nesting narrows, list values merge,
    # and a dotted option path is just another value.
    nested = run ctx [
      {
        hosts = [
          "khion"
          "lumi"
        ];
        packages = [ "base" ];
        children = [
          {
            users = [ "feltfomo" ];
            packages = [ "feltfomo-extra" ];
          }
          {
            hosts = [ "khion" ];
            services.hypridle.enable = true;
          }
        ];
      }
    ];

    # a file-link entry as its own self-labeled unit, merged with a global one --
    # the same owner keys ride a file-link that ride a block.
    files = run ctx [
      {
        files = [
          {
            dest = ".config/a";
            src = "/a";
          }
        ];
      }
      {
        users = [ "feltfomo" ];
        files = [
          {
            dest = ".config/b";
            src = "/b";
          }
        ];
      }
    ];
  };

  # deepSeq drives the lazy check/merge throws so tryEval catches the impossible
  # case below.
  throws = x: !(builtins.tryEval (builtins.deepSeq x x)).success;

  checks = [
    {
      name = "untagged is global";
      pass = results.global == { pkg = "everyone"; };
    }
    {
      name = "host hit";
      pass = results.hostHit == { pkg = "khion-only"; };
    }
    {
      name = "host miss drops";
      pass = results.hostMiss == { };
    }
    {
      name = "user hit";
      pass = results.userHit == { pkg = "feltfomo-only"; };
    }
    {
      name = "user miss drops";
      pass = results.userMiss == { };
    }
    {
      name = "exceptHosts active";
      pass = results.exceptHostActive == { pkg = "not-lumi"; };
    }
    {
      name = "exceptHosts inactive drops";
      pass = results.exceptHostInactive == { };
    }
    {
      name = "exceptUsers active";
      pass = results.exceptUserActive == { pkg = "not-grandpa"; };
    }
    {
      name = "exceptUsers inactive drops";
      pass = results.exceptUserInactive == { };
    }
    {
      name = "when hit";
      pass = results.whenHit == { pkg = "nvidia-only"; };
    }
    {
      name = "when miss drops";
      pass = results.whenMiss == { };
    }
    {
      name = "nested narrow + merge + option path";
      pass =
        results.nested == {
          packages = [
            "base"
            "feltfomo-extra"
          ];
          services.hypridle.enable = true;
        };
    }
    {
      name = "file-link entries merge across units";
      pass =
        results.files == {
          files = [
            {
              dest = ".config/a";
              src = "/a";
            }
            {
              dest = ".config/b";
              src = "/b";
            }
          ];
        };
    }
    {
      name = "cross-host user claim still impossible through the surface";
      pass = throws (
        run ctx [
          {
            hosts = [ "khion" ];
            children = [
              {
                users = [ "grandpa" ];
                pkg = "x";
              }
            ];
          }
        ]
      );
    }
    {
      name = "misshaped reserved key throws at author time";
      pass = throws (
        run ctx [
          {
            users = {
              alice = { };
            };
            pkg = "x";
          }
        ]
      );
    }
  ];

  failing = builtins.filter (c: !c.pass) checks;

  ok =
    if failing == [ ] then
      true
    else
      throw "ownerships surface tests FAILED: ${lib.concatMapStringsSep ", " (c: c.name) failing}";
in
{
  inherit results ok;
}
