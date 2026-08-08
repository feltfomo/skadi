{ lib, pkgs }:
let
  ownerships = import ../../ownerships { inherit lib; };
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

  containsInOrder =
    fragments: text:
    if fragments == [ ] then
      true
    else
      let
        fragment = builtins.head fragments;
        parts = lib.splitString fragment text;
      in
      builtins.length parts > 1
      && containsInOrder (builtins.tail fragments) (lib.concatStringsSep fragment (builtins.tail parts));

  resolve = units: ctx: lib.foldl' merge { } (map (collect ctx) units);
  resolveSystem = resolve;
  # the fake resolver is already ctx-pure, so the prepared door is the same
  # function; only program.nix's wiring of the split is under test here.
  resolvePrepared = resolve;
  program = import ../../program.nix {
    inherit
      lib
      resolve
      resolveSystem
      resolvePrepared
      ;
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
  caelestiaCli = builtins.fromJSON (builtins.readFile ../../../../configs/caelestia/cli.json);

  declarationsOfWith =
    args: spec:
    let
      result = spec.nixos args;
      declarationsModule = builtins.head (
        builtins.filter (module: builtins.isAttrs module && module ? lexicon) result.imports
      );
    in
    declarationsModule.lexicon.furnish.declarations;

  declarationsOf = declarationsOfWith moduleArgs;

  packageOnly = program { pkg = pkgs': pkgs'.hello; };
  fileOnly = program {
    files = [
      {
        dest = ".config/example";
        src = ../../program.nix;
      }
    ];
  };
  combined = program {
    pkg = pkgs': pkgs'.hello;
    files = [
      {
        dest = ".config/example";
        src = ../../program.nix;
      }
    ];
  };
  directoryOnly = program {
    directories = [
      {
        src = ../../krisis;
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
    theme = {
      id = "example";
      renderers.noctalia = {
        source = ../../krisis/safe-render.nix;
        output = ".config/example/safe-render.nix";
      };
    };
  };
  directoryDeclarations = declarationsOf directoryOnly;
  directoryDestinations = map (declaration: declaration.destination) directoryDeclarations;

  dmsOnly = program {
    theme = {
      id = "dms-example";
      renderers.dms = {
        source = ../../program.nix;
        output = ".config/example/dms.conf";
        native.compare_to = "dark";
      };
    };
  };
  dmsDestinations = map (declaration: declaration.destination) (declarationsOf dmsOnly);

  illogicalImpulseOnly = program {
    theme = {
      id = "illogical-impulse-example";
      renderers.illogical-impulse = {
        source = ../../program.nix;
        output = ".config/example/illogical-impulse.conf";
        native.compare_to = "dark";
      };
    };
  };
  illogicalImpulseDestinations = map (declaration: declaration.destination) (
    declarationsOf illogicalImpulseOnly
  );

  end4PcOnly = program {
    theme = {
      id = "end4-pc-example";
      renderers.end4-pc = {
        source = ../../program.nix;
        output = ".config/example/end4-pc.conf";
        native.compare_to = "dark";
      };
    };
  };
  end4PcDestinations = map (declaration: declaration.destination) (declarationsOf end4PcOnly);

  caelestiaOnly = program {
    theme = {
      id = "caelestia-example";
      renderers.caelestia = {
        source = ../../program.nix;
        output = ".config/example/caelestia.conf";
        reload = "pkill -SIGUSR1 example";
      };
    };
  };
  caelestiaDestinations = map (declaration: declaration.destination) (declarationsOf caelestiaOnly);

  caelestiaMulti = program {
    theme = {
      id = "caelestia-multi";
      templates = [
        {
          subId = "zeta";
          renderers.caelestia = {
            source = ../../program.nix;
            output = ".config/example/zeta.conf";
            reload = "printf zeta";
          };
        }
        {
          subId = "alpha";
          renderers.caelestia = {
            source = ../../program.nix;
            output = ".config/example/alpha.conf";
            reload = "printf alpha";
          };
        }
      ];
    };
  };
  caelestiaMultiDeclarations = declarationsOf caelestiaMulti;
  caelestiaMultiDestinations = lib.sort builtins.lessThan (
    map (declaration: declaration.destination) caelestiaMultiDeclarations
  );
  caelestiaMultiHook = builtins.head (
    builtins.filter (
      declaration: declaration.destination == ".config/caelestia/theme-hooks/caelestia-multi"
    ) caelestiaMultiDeclarations
  );
  caelestiaMultiHookScript = builtins.readFile caelestiaMultiHook.source.value;
  caelestiaPublishFragments = [
    "$HOME/.local/state/caelestia/theme/caelestia-multi-alpha-program.nix"
    "$HOME/.config/example/alpha.conf"
    "$HOME/.local/state/caelestia/theme/caelestia-multi-zeta-program.nix"
    "$HOME/.config/example/zeta.conf"
    "printf alpha"
    "printf zeta"
  ];

  dualTheme = program {
    theme = {
      id = "shared";
      source = ../../program.nix;
      output = ".config/example/shared.conf";
      renderers.noctalia.sharedWith = [
        "dms"
        "illogical-impulse"
        "end4-pc"
        "caelestia"
      ];
    };
  };
  dualThemeDestinations = map (declaration: declaration.destination) (declarationsOf dualTheme);

  reverseSharedTheme = program {
    theme = {
      id = "reverse-shared";
      source = ../../program.nix;
      output = ".config/example/reverse-shared.conf";
      renderers.dms.sharedWith = [ "noctalia" ];
    };
  };
  reverseSharedDestinations = map (declaration: declaration.destination) (
    declarationsOf reverseSharedTheme
  );
  writableDeclaration = builtins.head (
    builtins.filter (
      declaration: declaration.destination == ".config/example/default.nix"
    ) directoryDeclarations
  );

  subtreeDirectory = program {
    directories = [
      {
        src = ../../furnish;
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
        src = ../../program.nix;
      }
    ];
  };
  exceptFeltfomo = program {
    files = [
      {
        exceptUsers = [ "feltfomo" ];
        dest = ".config/except-user";
        src = ../../program.nix;
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
        src = ../../program.nix;
        typo = true;
      }
    ];
  };
  unknownDmsField = program {
    theme = {
      id = "invalid";
      renderers.dms = {
        source = ../../program.nix;
        output = ".config/invalid";
        typo = true;
      };
    };
  };
  unsupportedCaelestiaNative = program {
    theme = {
      id = "invalid-native";
      renderers.caelestia = {
        source = ../../program.nix;
        output = ".config/invalid-native";
        native.format = "unsupported";
      };
    };
  };
  emptyRenderer = program {
    theme = {
      id = "empty-renderer";
      renderers.dms = { };
    };
  };
  inheritedRendererFields = program {
    theme = {
      id = "inherited-renderer";
      source = ../../program.nix;
      output = ".config/inherited-renderer";
      placedAs = "shared.nix";
      renderers = {
        dms = { };
        noctalia.placedAs = "override.nix";
      };
    };
  };
  inheritedRendererDeclarations = declarationsOf inheritedRendererFields;
  inheritedRendererDestinations = map (
    declaration: declaration.destination
  ) inheritedRendererDeclarations;
  unknownSharedShell = program {
    theme = {
      id = "unknown-shared-shell";
      source = ../../program.nix;
      output = ".config/unknown-shared-shell";
      renderers.noctalia.sharedWith = [ "ds" ];
    };
  };
  duplicateSharedShell = program {
    theme = {
      id = "duplicate-shared-shell";
      source = ../../program.nix;
      output = ".config/duplicate-shared-shell";
      renderers.noctalia.sharedWith = [
        "dms"
        "dms"
      ];
    };
  };
  selfSharedShell = program {
    theme = {
      id = "self-shared-shell";
      source = ../../program.nix;
      output = ".config/self-shared-shell";
      renderers.noctalia.sharedWith = [ "noctalia" ];
    };
  };
  overlappingSharedShell = program {
    theme = {
      id = "overlapping-shared-shell";
      source = ../../program.nix;
      output = ".config/overlapping-shared-shell";
      renderers = {
        noctalia.sharedWith = [ "dms" ];
        dms = { };
      };
    };
  };
  invalidPolicy = program {
    files = [
      {
        dest = ".config/policy";
        src = ../../program.nix;
        onConflict = "merge";
      }
    ];
  };
  excludedOverride = program {
    directories = [
      {
        src = ../../furnish;
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
        src = ../../furnish;
        dest = ".config/furnish-source";
        exclude = [ "coordinator" ];
      }
    ];
    theme = {
      id = "excluded";
      renderers.noctalia = {
        source = ../../furnish/coordinator/Cargo.toml;
        output = ".config/excluded.toml";
      };
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
  inactiveTheme = program {
    theme = {
      id = "inactive-theme";
      when = _: false;
      renderers.caelestia = {
        source = throw "forced inactive theme source";
        output = ".config/inactive-theme";
      };
    };
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
        src = ../../program.nix;
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
  inactiveThemeResult = builtins.tryEval (builtins.deepSeq (inactiveTheme.nixos moduleArgs) true);
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
  unsupportedCaelestiaNativeResult = builtins.tryEval (
    builtins.deepSeq (unsupportedCaelestiaNative.nixos moduleArgs) true
  );
  emptyRendererResult = builtins.tryEval (builtins.deepSeq (emptyRenderer.nixos moduleArgs) true);
  unknownSharedShellResult = builtins.tryEval (
    builtins.deepSeq (unknownSharedShell.nixos moduleArgs) true
  );
  duplicateSharedShellResult = builtins.tryEval (
    builtins.deepSeq (duplicateSharedShell.nixos moduleArgs) true
  );
  selfSharedShellResult = builtins.tryEval (builtins.deepSeq (selfSharedShell.nixos moduleArgs) true);
  overlappingSharedShellResult = builtins.tryEval (
    builtins.deepSeq (overlappingSharedShell.nixos moduleArgs) true
  );
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
    inactive-theme-adapter-stays-lazy = inactiveThemeResult.success;
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
      && !(builtins.any (
        destination: lib.hasPrefix ".config/matugen/dms/configs/" destination
      ) dmsDestinations);
    illogical-impulse-templates-lower-to-independent-fragments = builtins.elem ".config/illogical-impulse/matugen/templates/illogical-impulse-example/program.nix" illogicalImpulseDestinations;
    end4-pc-templates-lower-to-independent-fragments = builtins.elem ".config/end4-pc/matugen/templates/end4-pc-example/program.nix" end4PcDestinations;
    caelestia-templates-lower-to-state-publishers =
      builtins.elem ".config/caelestia/templates/caelestia-example-program.nix" caelestiaDestinations
      && builtins.elem ".config/caelestia/theme-hooks/caelestia-example" caelestiaDestinations;
    caelestia-multi-output-destinations-are-exact =
      caelestiaMultiDestinations == [
        ".config/caelestia/templates/caelestia-multi-alpha-program.nix"
        ".config/caelestia/templates/caelestia-multi-zeta-program.nix"
        ".config/caelestia/theme-hooks/caelestia-multi"
      ];
    caelestia-publishers-are-strict-and-transactionally-ordered =
      lib.hasInfix "set -eu" caelestiaMultiHookScript
      && containsInOrder caelestiaPublishFragments caelestiaMultiHookScript;
    caelestia-aggregate-post-hook-is-strict = lib.hasPrefix "set -eu;" caelestiaCli.theme.postHook;
    shared-registration-emits-all-backends =
      builtins.elem ".config/noctalia/templates/shared/program.nix" dualThemeDestinations
      && builtins.elem ".config/noctalia/shared.toml" dualThemeDestinations
      && builtins.elem ".config/matugen/dms/templates/shared/program.nix" dualThemeDestinations
      && builtins.elem ".config/illogical-impulse/matugen/templates/shared/program.nix" dualThemeDestinations
      && builtins.elem ".config/end4-pc/matugen/templates/shared/program.nix" dualThemeDestinations
      && builtins.elem ".config/caelestia/templates/shared-program.nix" dualThemeDestinations
      && builtins.elem ".config/caelestia/theme-hooks/shared" dualThemeDestinations
      && !(builtins.any (
        destination: lib.hasPrefix ".config/matugen/dms/configs/" destination
      ) dualThemeDestinations);
    shared-registration-is-direction-independent =
      builtins.elem ".config/noctalia/templates/reverse-shared/program.nix" reverseSharedDestinations
      && builtins.elem ".config/noctalia/reverse-shared.toml" reverseSharedDestinations
      && builtins.elem ".config/matugen/dms/templates/reverse-shared/program.nix" reverseSharedDestinations;
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
    caelestia-native-fields-are-rejected = !unsupportedCaelestiaNativeResult.success;
    empty-renderers-are-rejected = !emptyRendererResult.success;
    inherited-renderer-fields-are-supported =
      builtins.elem ".config/matugen/dms/templates/inherited-renderer/shared.nix" inheritedRendererDestinations
      && builtins.elem ".config/noctalia/templates/inherited-renderer/override.nix" inheritedRendererDestinations;
    unknown-shared-shells-are-rejected = !unknownSharedShellResult.success;
    duplicate-shared-shells-are-rejected = !duplicateSharedShellResult.success;
    self-shared-shells-are-rejected = !selfSharedShellResult.success;
    overlapping-shared-shells-are-rejected = !overlappingSharedShellResult.success;
    invalid-conflict-policies-are-rejected = !invalidPolicyResult.success;
    overrides-beneath-excluded-subtrees-are-rejected = !excludedOverrideResult.success;
    theme-sources-beneath-excluded-subtrees-are-rejected = !excludedThemeResult.success;
  };

  failing = builtins.attrNames (lib.filterAttrs (_: value: !value) tests);
  ok =
    if failing == [ ] then true else throw "program tests failed: ${lib.concatStringsSep ", " failing}";
}
