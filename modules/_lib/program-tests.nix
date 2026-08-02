{ lib, pkgs }:
let
  claimKeys = [
    "hosts"
    "users"
    "exceptHosts"
    "exceptUsers"
    "when"
  ];

  # the test resolver keeps the program boundary independent from the fleet roster.
  collect =
    unit:
    let
      active = !(unit ? when) || unit.when { };
      own = removeAttrs unit (claimKeys ++ [ "children" ]);
    in
    if !active then { } else lib.foldl' lib.recursiveUpdate own (map collect (unit.children or [ ]));

  resolve = units: _: lib.foldl' lib.recursiveUpdate { } (map collect units);
  resolveSystem = resolve;
  program = import ./program.nix {
    inherit lib resolve resolveSystem;
    filePrincipals = _: [
      {
        authority = {
          scope = "user";
          identity = "feltfomo";
        };
      }
    ];
    hostUserNames = _: [ "feltfomo" ];
  };

  moduleArgs = {
    inherit lib pkgs;
    config = {
      networking.hostName = "test";
      lexicon.furnish.declarations = [ { } ];
    };
    host = {
      name = "test";
    };
    user = {
      name = "feltfomo";
    };
  };

  packageOnly = program { pkg = pkgs': pkgs'.hello; };
  fileOnly = program {
    files = [
      {
        dest = ".config/example";
        src = ./program.nix;
      }
    ];
  };
  combined = program {
    pkg = pkgs': pkgs'.hello;
    files = [
      {
        dest = ".config/example";
        src = ./program.nix;
      }
    ];
  };
  inactiveMalformed = program {
    files = [
      {
        when = _: false;
        dest = 1;
      }
    ];
  };
  selectedMalformed = program {
    files = [
      {
        dest = 1;
      }
    ];
  };
  inactiveResult = builtins.tryEval (builtins.deepSeq (inactiveMalformed.nixos moduleArgs) true);
  malformedResult = builtins.tryEval (builtins.deepSeq (selectedMalformed.nixos moduleArgs) true);
in
{
  tests = {
    bounded-output-shapes =
      builtins.attrNames packageOnly == [ "homeManager" ]
      && builtins.attrNames fileOnly == [ "nixos" ]
      &&
        builtins.attrNames combined == [
          "homeManager"
          "nixos"
        ];
    package-only-shape = packageOnly ? homeManager && !(packageOnly ? nixos);
    file-only-shape = fileOnly ? nixos && !(fileOnly ? homeManager);
    combined-shape = combined ? homeManager && combined ? nixos;
    inactive-payload-stays-lazy = inactiveResult.success;
    selected-payload-is-validated = !malformedResult.success;
  };

  ok = lib.all (value: value) (builtins.attrValues tests);
}
