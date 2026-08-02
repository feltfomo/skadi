{ lib, pkgs }:
let
  claimKeys = [
    "hosts"
    "users"
    "exceptHosts"
    "exceptUsers"
    "when"
  ];

  merge =
    left: right:
    lib.zipAttrsWith
      (
        _: values:
        if builtins.all builtins.isList values then
          builtins.concatLists values
        else if builtins.all builtins.isAttrs values then
          lib.foldl' merge { } values
        else
          lib.last values
      )
      [
        left
        right
      ];

  # The test resolver isolates the program boundary from the fleet roster.
  collect =
    ctx: unit:
    let
      hostName = ctx.host.name or null;
      userName = ctx.user.name or null;
      active =
        (!(unit ? when) || unit.when ctx)
        && (!(unit ? hosts) || builtins.elem hostName unit.hosts)
        && (!(unit ? users) || builtins.elem userName unit.users)
        && (!(unit ? exceptHosts) || !(builtins.elem hostName unit.exceptHosts))
        && (!(unit ? exceptUsers) || !(builtins.elem userName unit.exceptUsers));
      own = removeAttrs unit (claimKeys ++ [ "children" ]);
    in
    if !active then { } else lib.foldl' merge own (map (collect ctx) (unit.children or [ ]));

  resolve = units: ctx: lib.foldl' merge { } (map (collect ctx) units);
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
    host.name = "test";
    user.name = "feltfomo";
  };

  declarationsOf =
    spec:
    let
      result = spec.nixos moduleArgs;
    in
    (builtins.elemAt result.imports 1).lexicon.furnish.declarations;

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
  directoryOnly = program {
    directories = [
      {
        src = ./krisis;
        dest = ".config/example";
        files = [
          {
            names = [ "default.nix" ];
            representation = "writable";
            onConflict = "runtime-wins";
          }
          {
            names = [ "diagnostics.nix" ];
            hosts = [ "lumi" ];
          }
        ];
      }
    ];
    theme.noctalia = {
      id = "example";
      source = ./krisis/safe-render.nix;
      output = ".config/example/safe-render.nix";
    };
  };
  directoryDeclarations = declarationsOf directoryOnly;
  directoryDestinations = map (declaration: declaration.destination) directoryDeclarations;
  writableDeclaration = builtins.head (
    builtins.filter (
      declaration: declaration.destination == ".config/example/default.nix"
    ) directoryDeclarations
  );

  inactiveMalformed = program {
    files = [
      {
        when = _: false;
        dest = 1;
      }
    ];
  };
  inactiveDirectory = program {
    directories = [
      {
        when = _: false;
        src = throw "forced inactive directory source";
        dest = ".config/inactive";
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
  selectedMalformedDirectory = program {
    directories = [
      {
        src = ./program.nix;
        dest = ".config/not-a-directory";
      }
    ];
  };

  inactiveResult = builtins.tryEval (builtins.deepSeq (inactiveMalformed.nixos moduleArgs) true);
  inactiveDirectoryResult = builtins.tryEval (
    builtins.deepSeq (inactiveDirectory.nixos moduleArgs) true
  );
  malformedResult = builtins.tryEval (builtins.deepSeq (selectedMalformed.nixos moduleArgs) true);
  malformedDirectoryResult = builtins.tryEval (
    builtins.deepSeq (selectedMalformedDirectory.nixos moduleArgs) true
  );
in
rec {
  tests = {
    bounded-output-shapes =
      builtins.attrNames packageOnly == [ "homeManager" ]
      && builtins.attrNames fileOnly == [ "nixos" ]
      && builtins.attrNames directoryOnly == [ "nixos" ]
      &&
        builtins.attrNames combined == [
          "homeManager"
          "nixos"
        ];
    package-only-shape = packageOnly ? homeManager && !(packageOnly ? nixos);
    file-only-shape = fileOnly ? nixos && !(fileOnly ? homeManager);
    combined-shape = combined ? homeManager && combined ? nixos;
    inactive-payload-stays-lazy = inactiveResult.success;
    inactive-directory-stays-lazy = inactiveDirectoryResult.success;
    selected-payload-is-validated = !malformedResult.success;
    selected-directory-is-validated = !malformedDirectoryResult.success;
    directory-members-expand-to-files = builtins.elem ".config/example/default.nix" directoryDestinations;
    inactive-overrides-do-not-fall-back =
      !(builtins.elem ".config/example/diagnostics.nix" directoryDestinations);
    noctalia-sources-are-reserved =
      !(builtins.elem ".config/example/safe-render.nix" directoryDestinations)
      && builtins.elem ".config/noctalia/templates/example/safe-render.nix" directoryDestinations;
    writable-overrides-are-first-class =
      writableDeclaration.representation == "writable"
      && writableDeclaration.onConflict == "runtime-wins";
  };

  ok = lib.all (value: value) (builtins.attrValues tests);
}
