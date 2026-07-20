{
  lib,
  resolve,
  resolveSystem,
}:
let
  ownerships = import ../ownerships { inherit lib; };
  krisis = import ../krisis { inherit lib; };
  furnish = import ./default.nix {
    inherit
      lib
      resolve
      resolveSystem
      ;
  };
  inherit (furnish) contract;

  ctx = {
    host = {
      name = "khion";
      system = "x86_64-linux";
    };
    user.name = "feltfomo";
  };

  sample = {
    label = "sample-config";
    users = [ "feltfomo" ];
    filesystemNamespace = "x86_64-linux/khion";
    authority = {
      scope = "user";
      identity = "feltfomo";
    };
    managedRoot = "/home/feltfomo";
    destination = ".config/furnish/sample.conf";
    representation = contract.capabilities.symlink;
    source = {
      kind = "path";
      value = ./default.nix;
    };
    provenance.source = "modules/_lib/furnish/tests.nix";
  };

  mkExecutor =
    {
      identity,
      priority,
    }:
    {
      inherit
        identity
        priority
        ;
      enabled = true;
      protocolVersion = 1;
      capabilities = [
        contract.capabilities.lifecycleBaseline
        contract.capabilities.symlink
      ];
      materialize = declaration: {
        retainedArtifactTarget = builtins.path {
          path = declaration.source.value;
          name = "furnish-${declaration.label}";
        };
        cleanupStrategy = contract.strategies.exactSymlinkTarget;
        selfHealStrategy = contract.strategies.exactSymlinkTarget;
      };
    };

  preferredExecutor = mkExecutor {
    identity = "executor/a";
    priority = 10;
  };
  tiedExecutor = mkExecutor {
    identity = "executor/z";
    priority = 10;
  };
  unusedPoisonExecutor = {
    identity = "executor/unused";
    priority = 0;
    enabled = true;
    protocolVersion = 1;
    capabilities = [ "unrelated" ];
    materialize = throw "forced an unused executor implementation";
  };
  executors = [
    tiedExecutor
    unusedPoisonExecutor
    preferredExecutor
  ];

  compile =
    declarations:
    furnish.compile {
      inherit
        declarations
        executors
        ctx
        ;
    };

  sampleResult = compile [ sample ];
  sampleEntry = builtins.head sampleResult.manifestData;

  second = sample // {
    label = "other-config";
    destination = ".config/furnish/other.conf";
  };
  orderedA = compile [
    sample
    second
  ];
  orderedB = compile [
    second
    sample
  ];

  poisonDerivation = {
    type = "derivation";
    name = "poison-package";
    drvPath = throw "forced a derivation-shaped value";
    outPath = throw "forced a derivation-shaped value";
  };
  poisonSecret.token = throw "forced a secret-shaped value";
  poisonPayload = {
    package = poisonDerivation;
    secret = poisonSecret;
  };

  inactive = sample // {
    label = "inactive-poison";
    hosts = [ "lumi" ];
    destination = ".config/furnish/inactive.conf";
    source = sample.source // {
      value = throw "forced an inactive ownership payload";
    };
  };
  inactiveResult = compile [
    sample
    inactive
  ];

  noCapable = sample // {
    label = "no-capable-executor";
    source = sample.source // {
      value = poisonPayload;
    };
  };

  impossible = sample // {
    label = "ownership-impossible";
    users = [ "nobody" ];
    source = sample.source // {
      value = poisonPayload;
    };
  };

  untagged = removeAttrs sample [ "users" ];
  offUntaggedResult = furnish.compile {
    declarations = [ untagged ];
    inherit executors ctx;
    provider = furnish.core.offProvider;
  };
  offTaggedResult = furnish.compile {
    declarations = [ sample ];
    inherit executors ctx;
    provider = furnish.core.offProvider;
  };

  throws = value: !(builtins.tryEval (builtins.deepSeq value value)).success;

  inertCore = import ./core.nix {
    inherit lib contract krisis;
    inherit (ownerships) claimKeys;
    resolve = throw "no-op forced the user ownership door";
    resolveSystem = throw "no-op forced the system ownership door";
  };
  raw = {
    ordinary = {
      enabled = true;
      values = [
        1
        2
      ];
    };
  };
  noOp = inertCore.compile { inherit raw; };

  systemCore = import ./core.nix {
    inherit lib contract krisis;
    inherit (ownerships) claimKeys;
    resolve = throw "a system declaration used the user ownership door";
    resolveSystem = units: _ctx: {
      entries = builtins.concatMap (unit: unit.value.entries or [ ]) units;
    };
  };
  systemDeclaration = (removeAttrs sample [ "users" ]) // {
    label = "system-config";
    filesystemNamespace = "x86_64-linux/khion";
    authority = {
      scope = "system";
      identity = "x86_64-linux/khion";
    };
    managedRoot = "/etc";
    destination = "furnish/sample.conf";
  };
  systemResult = systemCore.compile {
    declarations = [ systemDeclaration ];
    inherit executors ctx;
  };

  diagnosticText = furnish.core.renderDiagnostic (
    furnish.core.diagnostic "capability-selection" "no-capable-executor" "sample" "no executor matched"
  );

  manifestKeys = builtins.attrNames sampleEntry;
  artifactTarget = sampleEntry.retainedArtifactTarget;
  manifestContext = builtins.getContext sampleResult.manifestJson;

  # The load-bearing gate probe is flipped temporarily during validation. If
  # this value is false and `nix flake check` stays green, the check isn't wired.
  wiringProbe = true;

  checks = [
    {
      name = "ownerships facade keeps internals private and supplies furnish claim keys";
      pass =
        !(ownerships ? engine)
        && !(ownerships ? engineArgsFor)
        && !(ownerships ? resolveWith)
        && furnish.core.isOwnerTagged (lib.genAttrs ownerships.claimKeys (_: [ ]));
    }
    {
      name = "sample manifest is byte-stable and entry order is canonical";
      pass =
        sampleResult.manifestJson == (compile [ sample ]).manifestJson
        && toString sampleResult.manifestPath == toString (compile [ sample ]).manifestPath
        && orderedA.manifestJson == orderedB.manifestJson
        &&
          map (entry: entry.filesystemIdentity.canonical) orderedA.manifestData == [
            "x86_64-linux/khion:/home/feltfomo/.config/furnish/other.conf"
            "x86_64-linux/khion:/home/feltfomo/.config/furnish/sample.conf"
          ];
    }
    {
      name = "manifest keeps identity authority root and executor separate";
      pass =
        sampleEntry.filesystemIdentity == {
          namespace = "x86_64-linux/khion";
          destination = "/home/feltfomo/.config/furnish/sample.conf";
          canonical = "x86_64-linux/khion:/home/feltfomo/.config/furnish/sample.conf";
        }
        &&
          sampleEntry.authority == {
            scope = "user";
            identity = "feltfomo";
          }
        && sampleEntry.managedRoot == "/home/feltfomo"
        &&
          sampleEntry.executor == {
            identity = "executor/a";
            protocolVersion = 1;
          };
    }
    {
      name = "manifest is safe serializable data with enum lifecycle strategies";
      pass =
        (builtins.tryEval (builtins.deepSeq (builtins.toJSON sampleResult.manifestData) true)).success
        &&
          manifestKeys == [
            "authority"
            "cleanupStrategy"
            "executor"
            "filesystemIdentity"
            "managedRoot"
            "provenance"
            "representation"
            "retainedArtifactTarget"
            "schemaVersion"
            "selfHealStrategy"
          ]
        && sampleEntry.cleanupStrategy == "exact-symlink-target"
        && sampleEntry.selfHealStrategy == "exact-symlink-target"
        && !(sampleEntry ? source);
    }
    {
      name = "manifest context pins a dedicated artifact object";
      pass =
        lib.hasPrefix "/nix/store/" artifactTarget
        && artifactTarget != toString ./default.nix
        && builtins.elem (builtins.unsafeDiscardStringContext artifactTarget) (
          builtins.attrNames manifestContext
        );
    }
    {
      name = "inactive ownership: deepSeq forces no inactive payload";
      pass = (builtins.tryEval (builtins.deepSeq inactiveResult.manifestData true)).success;
    }
    {
      name = "inactive ownership: exactly one entry survives selection";
      pass = builtins.length inactiveResult.manifestData == 1;
    }
    {
      name = "inactive ownership: surviving entry identity equals the sample entry";
      pass =
        (builtins.head inactiveResult.manifestData).filesystemIdentity.canonical
        == sampleEntry.filesystemIdentity.canonical;
    }
    {
      name = "inactive ownership: manifest equals the sample-only manifest";
      pass = inactiveResult.manifestData == sampleResult.manifestData;
    }
    {
      name = "unused executor: materialize stays unforced when a capable executor exists";
      pass = (builtins.tryEval (builtins.deepSeq sampleResult.manifestData true)).success;
    }
    {
      name = "no capable executor is a structured furnish error without forcing payload";
      pass =
        throws (
          furnish.compile {
            declarations = [ noCapable ];
            executors = [ unusedPoisonExecutor ];
            inherit ctx;
          }
        )
        &&
          diagnosticText == "furnish: capability-selection/no-capable-executor: sample: no executor matched";
    }
    {
      name = "ownership impossible errors propagate through furnish without a catch or wrapper";
      pass = throws (compile [ impossible ]);
    }
    {
      name = "off mode passes an untagged declaration byte-identical to enabled mode";
      pass =
        offUntaggedResult.manifestJson == (compile [ untagged ]).manifestJson
        && builtins.length offUntaggedResult.manifestData == 1;
    }
    {
      name = "off mode rejects an owner-tagged declaration instead of silently passing it";
      pass = throws offTaggedResult;
    }
    {
      name = "empty declarations have one inert encoding and don't enter ownership";
      pass =
        noOp.manifestData == [ ]
        && noOp.manifestPath == null
        && noOp.manifestJson == "[]"
        && noOp.raw == raw;
    }
    {
      name = "raw config is returned byte-for-byte adjacent to furnish output";
      pass = (furnish.compile { inherit raw; }).raw == raw;
    }
    {
      name = "authority chooses the system ownership door";
      pass =
        (builtins.head systemResult.manifestData).authority.identity == "x86_64-linux/khion"
        &&
          (builtins.head systemResult.manifestData).filesystemIdentity.destination
          == "/etc/furnish/sample.conf";
    }
    {
      name = "duplicate filesystem identities fail after canonical ordering";
      pass = throws (compile [
        sample
        (sample // { label = "duplicate"; })
      ]);
    }
    {
      name = "furnish check wiring probe";
      pass = wiringProbe;
    }
  ];

  failing = builtins.filter (check: !check.pass) checks;
  ok =
    if failing == [ ] then
      true
    else
      throw "furnish tests FAILED: ${lib.concatMapStringsSep ", " (check: check.name) failing}";
in
{
  inherit
    checks
    ok
    sampleResult
    ;
}
