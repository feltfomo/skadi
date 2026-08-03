{ lib, pkgs }:
let
  ownerships = import ./ownerships { inherit lib; };
  inherit (ownerships) claimKeys;

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

  # the test resolver isolates the program boundary from the fleet roster
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
    filePrincipals = args: [
      {
        authority = {
          scope = "user";
          identity = args.user.name;
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

  declarationsOfWith =
    args: spec:
    let
      result = spec.nixos args;
    in
    (builtins.elemAt result.imports 1).lexicon.furnish.declarations;

  declarationsOf = declarationsOfWith moduleArgs;

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

  dmsOnly = program {
    theme.dms = {
      id = "dms-example";
      source = ./program.nix;
      output = ".config/example/dms.conf";
      native = {
        compare_to = "dark";
      };
    };
  };
  dmsDestinations = map (declaration: declaration.destination) (declarationsOf dmsOnly);

  dualTheme = program {
    theme = {
      noctalia = {
        id = "shared";
        source = ./program.nix;
        output = ".config/example/shared.conf";
      };
      dms = {
        id = "shared";
        source = ./program.nix;
        output = ".config/example/shared.conf";
      };
    };
  };
  dualThemeDestinations = map (declaration: declaration.destination) (declarationsOf dualTheme);
  writableDeclaration = builtins.head (
    builtins.filter (
      declaration: declaration.destination == ".config/example/default.nix"
    ) directoryDeclarations
  );

  subtreeDirectory = program {
    directories = [
      {
        src = ./furnish;
        dest = ".config/furnish-source";
        exclude = [ "coordinator" ];
      }
    ];
  };
  subtreeDeclarations = declarationsOf subtreeDirectory;
  subtreeDestinations = map (declaration: declaration.destination) subtreeDeclarations;

  userOnly = program {
    files = [
      {
        users = [ "feltfomo" ];
        dest = ".config/user-only";
        src = ./program.nix;
      }
    ];
  };
  exceptFeltfomo = program {
    files = [
      {
        exceptUsers = [ "feltfomo" ];
        dest = ".config/except-user";
        src = ./program.nix;
      }
    ];
  };
  grandpaArgs = moduleArgs // {
    user.name = "grandpa";
  };

  unknownFileField = program {
    files = [
      {
        dest = ".config/unknown";
        src = ./program.nix;
        typo = true;
      }
    ];
  };
  unknownDmsField = program {
    theme.dms = {
      id = "invalid";
      source = ./program.nix;
      output = ".config/invalid";
      typo = true;
    };
  };
  invalidPolicy = program {
    files = [
      {
        dest = ".config/policy";
        src = ./program.nix;
        onConflict = "merge";
      }
    ];
  };
  excludedOverride = program {
    directories = [
      {
        src = ./furnish;
        dest = ".config/furnish-source";
        exclude = [ "coordinator" ];
        files = [
          {
            names = [ "coordinator/src/main.rs" ];
            representation = "writable";
          }
        ];
      }
    ];
  };
  excludedTheme = program {
    directories = [
      {
        src = ./furnish;
        dest = ".config/furnish-source";
        exclude = [ "coordinator" ];
      }
    ];
    theme.noctalia = {
      id = "excluded";
      source = ./furnish/coordinator/Cargo.toml;
      output = ".config/excluded.toml";
    };
  };

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
  selectedMissingDirectory = program {
    directories = [
      {
        src = "${./.}/program-tests-missing-directory";
        dest = ".config/missing-directory";
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
  missingDirectoryResult = builtins.tryEval (
    builtins.deepSeq (selectedMissingDirectory.nixos moduleArgs) true
  );
  unknownFileFieldResult = builtins.tryEval (
    builtins.deepSeq (unknownFileField.nixos moduleArgs) true
  );
  unknownDmsFieldResult = builtins.tryEval (builtins.deepSeq (unknownDmsField.nixos moduleArgs) true);
  invalidPolicyResult = builtins.tryEval (builtins.deepSeq (invalidPolicy.nixos moduleArgs) true);
  excludedOverrideResult = builtins.tryEval (
    builtins.deepSeq (excludedOverride.nixos moduleArgs) true
  );
  excludedThemeResult = builtins.tryEval (builtins.deepSeq (excludedTheme.nixos moduleArgs) true);
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
    selected-nondirectory-source-is-rejected = !malformedDirectoryResult.success;
    selected-missing-directory-source-is-rejected = !missingDirectoryResult.success;
    directory-members-expand-to-files = builtins.elem ".config/example/default.nix" directoryDestinations;
    inactive-overrides-do-not-fall-back =
      !(builtins.elem ".config/example/diagnostics.nix" directoryDestinations);
    noctalia-sources-are-reserved =
      !(builtins.elem ".config/example/safe-render.nix" directoryDestinations)
      && builtins.elem ".config/noctalia/templates/example/safe-render.nix" directoryDestinations;
    dms-templates-lower-to-independent-fragments =
      builtins.elem ".config/matugen/dms/templates/dms-example/program.nix" dmsDestinations
      && builtins.elem ".config/matugen/dms/configs/dms-example.toml" dmsDestinations;
    explicit-dual-registration-emits-both-backends =
      builtins.elem ".config/noctalia/templates/shared/program.nix" dualThemeDestinations
      && builtins.elem ".config/noctalia/shared.toml" dualThemeDestinations
      && builtins.elem ".config/matugen/dms/templates/shared/program.nix" dualThemeDestinations
      && builtins.elem ".config/matugen/dms/configs/shared.toml" dualThemeDestinations;
    writable-overrides-are-first-class =
      writableDeclaration.representation == "writable"
      && writableDeclaration.onConflict == "runtime-wins";
    directory-subtrees-are-pruned =
      !(builtins.any (destination: lib.hasInfix "/coordinator/" destination) subtreeDestinations);
    directory-member-sources-stay-path-typed = builtins.all (
      declaration: builtins.isPath declaration.source.value
    ) subtreeDeclarations;
    user-claims-select-the-current-user =
      builtins.length (declarationsOf userOnly) == 1 && declarationsOfWith grandpaArgs userOnly == [ ];
    except-user-claims-select-everyone-else =
      declarationsOf exceptFeltfomo == [ ]
      && builtins.length (declarationsOfWith grandpaArgs exceptFeltfomo) == 1;
    unknown-file-fields-are-rejected = !unknownFileFieldResult.success;
    unknown-dms-fields-are-rejected = !unknownDmsFieldResult.success;
    invalid-conflict-policies-are-rejected = !invalidPolicyResult.success;
    overrides-beneath-excluded-subtrees-are-rejected = !excludedOverrideResult.success;
    theme-sources-beneath-excluded-subtrees-are-rejected = !excludedThemeResult.success;
  };

  ok = lib.all (value: value) (builtins.attrValues tests);
}
