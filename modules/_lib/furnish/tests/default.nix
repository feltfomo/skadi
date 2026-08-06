{
  lib,
  resolve,
  resolveSystem,
  principalContexts,
}:
let
  ownerships = import ../../ownerships { inherit lib; };
  krisis = import ../../krisis { inherit lib; };
  furnish = import ../default.nix {
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
      value = ../default.nix;
    };
    provenance.source = "modules/_lib/furnish/tests/default.nix";
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
  poisonType = {
    type = throw "forced a type-shaped value";
    token = throw "forced a type-shaped payload";
  };
  poisonNamedDerivation = {
    type = "derivation";
    name = throw "forced a derivation name";
    drvPath = throw "forced a derivation field";
  };
  poisonList = [
    "visible"
    (throw "forced a list payload")
  ];

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

  explicitPolicy = sample // {
    label = "explicit-policy";
    onConflict = contract.conflictPolicies.sourceWins;
  };
  explicitPolicyEntry = builtins.head (compile [ explicitPolicy ]).manifestData;
  bogusPolicy = sample // {
    label = "bogus-policy";
    onConflict = "merge";
  };

  malformedShape = {
    label = 1;
    filesystemNamespace = false;
    authority = {
      scope = "unknown";
    };
    managedRoot = 1;
    destination = false;
    representation = "";
    source = {
      kind = 1;
      value = throw "forced malformed shape payload";
    };
    onConflict = "merge";
  };
  malformedShapeDiagnostics = furnish.core.shapeDiagnostics malformedShape;
  malformedShapeCodes = map (item: item.code) malformedShapeDiagnostics;

  malformedExecutor = {
    identity = 1;
    priority = "first";
    enabled = "yes";
    protocolVersion = false;
    capabilities = [ 1 ];
    materialize = throw "forced malformed executor implementation";
  };
  malformedExecutorResult = builtins.tryEval (
    builtins.deepSeq (furnish.core.validateExecutors [ malformedExecutor ]) true
  );
  malformedShapeResult = builtins.tryEval (builtins.deepSeq malformedShapeDiagnostics true);

  invalidArtifactExecutor = preferredExecutor // {
    identity = "executor/invalid-artifact";
    materialize = _: {
      retainedArtifactTarget = { };
      cleanupStrategy = "unknown";
      selfHealStrategy = "unknown";
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

  inertCore = import ../core.nix {
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

  systemCore = import ../core.nix {
    inherit lib contract krisis;
    inherit (ownerships) claimKeys;
    resolve = throw "a system declaration used the user ownership door";
    # the stub mirrors the roster-bound door's merged-value contract: the
    # batched provider hands the resolver one unit tree whose leaves carry
    # per-declaration `value.entries` chunks under unique keys, and the merged
    # value unions every leaf's chunk.
    resolveSystem =
      units: _ctx:
      builtins.foldl' (merged: node: merged // node.value or { }) { } (
        builtins.concatMap (
          unit:
          let
            collect = node: [ node ] ++ builtins.concatMap collect (node.children or [ ]);
          in
          collect unit
        ) units
      );
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

  principalByScope =
    scope: builtins.head (builtins.filter (p: p.authority.scope == scope) principalContexts);
  userPrincipal = principalByScope "user";
  systemPrincipal = principalByScope "system";
  hostPrincipals = [
    systemPrincipal
    userPrincipal
  ];

  # a second user principal built here rather than taken from principalcontexts,
  # which comes from a single-user host and so cannot show per-user counting.
  secondUserPrincipal = userPrincipal // {
    authority = {
      scope = "user";
      identity = "grandpa";
    };
    ctx = userPrincipal.ctx // {
      user.name = "grandpa";
    };
  };
  twoUserPrincipals = [
    userPrincipal
    secondUserPrincipal
  ];
  rootedUserPrincipal = userPrincipal // {
    managedRoot = "/srv/furnish/feltfomo";
  };

  userClaim = (removeAttrs sample [ "users" ]) // {
    label = "user-claim";
    managedRoot = "/tmp";
    destination = "furnish/shared.conf";
    source = sample.source // {
      value = throw "forced active host-index payload";
    };
    generator = throw "forced active host-index generator";
    executor = throw "forced active host-index executor";
    provenance.source = "user-source.nix";
  };
  systemClaim = (removeAttrs systemDeclaration [ "users" ]) // {
    label = "system-claim";
    managedRoot = "/tmp";
    destination = "/tmp/furnish/shared.conf";
    source = systemDeclaration.source // {
      value = throw "forced system host-index payload";
    };
    provenance.source = "system-source.nix";
  };
  inactiveHostClaim = userClaim // {
    label = "inactive-host-poison";
    hosts = [ "lumi" ];
    destination = "furnish/inactive.conf";
    source = userClaim.source // {
      value = throw "forced ownership-excluded host-index payload";
    };
  };
  secondUserClaim = userClaim // {
    label = "second-user-claim";
    provenance.source = "second-user-source.nix";
  };
  secondCollisionUser = userClaim // {
    label = "other-user-claim";
    destination = "furnish/other.conf";
    provenance.source = "other-user-source.nix";
  };
  secondCollisionSystem = systemClaim // {
    label = "other-system-claim";
    destination = "furnish/other.conf";
    provenance.source = "other-system-source.nix";
  };
  canonicalSpelling = userClaim // {
    label = "canonical-spelling";
    destination = "furnish/./nested/../shared.conf/";
    provenance.source = "canonical-source.nix";
  };
  escaping = userClaim // {
    label = "escaping";
    destination = "../../etc/escaped.conf";
  };

  projectHost =
    declarations:
    builtins.concatMap (
      principal: furnish.core.projectPrincipal { inherit declarations principal; }
    ) hostPrincipals;
  collisionText =
    declarations:
    furnish.core.renderDiagnostics (furnish.core.collisionDiagnostics (projectHost declarations));

  crossCollisionText = collisionText [
    userClaim
    systemClaim
  ];
  samePrincipalCollisionText = collisionText [
    userClaim
    secondUserClaim
  ];
  threeClaimantText = collisionText [
    userClaim
    secondUserClaim
    systemClaim
  ];
  aggregateCollisionText = collisionText [
    userClaim
    systemClaim
    secondCollisionUser
    secondCollisionSystem
  ];
  expectedCrossCollisionText = "furnish: collision-detection/duplicate-filesystem-identity: x86_64-linux/khion:/tmp/furnish/shared.conf: claimed by system/x86_64-linux/khion (system-claim at system-source.nix), user/feltfomo (user-claim at user-source.nix)";
  expectedSamePrincipalCollisionText = "furnish: collision-detection/duplicate-filesystem-identity: x86_64-linux/khion:/tmp/furnish/shared.conf: claimed by user/feltfomo (second-user-claim at second-user-source.nix), user/feltfomo (user-claim at user-source.nix)";

  collisionEvidence = aggregateCollisionText;

  # frozen copy of the record kitty carried by hand, so the generated layer has
  # to keep producing it.
  kittyRecord = {
    label = "kitty.files[0]";
    filesystemNamespace = "x86_64-linux/khion";
    authority = {
      scope = "user";
      identity = "feltfomo";
    };
    managedRoot = "/home/feltfomo";
    destination = ".config/kitty/kitty.conf";
    representation = "symlink";
    source = {
      kind = "path";
      value = ../../../../configs/kitty/kitty.conf;
    };
    provenance.source = "modules/aspects/kitty.nix";
  };

  kittyEntry = {
    dest = ".config/kitty/kitty.conf";
    src = ../../../../configs/kitty/kitty.conf;
    label = "kitty.files[0]";
    provenance = "modules/aspects/kitty.nix";
  };

  kittyGenerated = furnish.files.mkDeclarations {
    filesystemNamespace = "x86_64-linux/khion";
    principals = hostPrincipals;
    files = [ kittyEntry ];
  };

  systemOnlyGenerated = furnish.files.mkDeclarations {
    filesystemNamespace = "x86_64-linux/khion";
    principals = [ systemPrincipal ];
    files = [ kittyEntry ];
  };

  noPrincipalGenerated = furnish.files.mkDeclarations {
    filesystemNamespace = "x86_64-linux/khion";
    principals = [ ];
    files = [ kittyEntry ];
  };

  twoUserGenerated = furnish.files.mkDeclarations {
    filesystemNamespace = "x86_64-linux/khion";
    principals = twoUserPrincipals;
    files = [ kittyEntry ];
  };

  rootedUserGenerated = furnish.files.mkDeclarations {
    filesystemNamespace = "x86_64-linux/khion";
    principals = [ rootedUserPrincipal ];
    files = [ kittyEntry ];
  };

  invalidArtifactResult = builtins.tryEval (
    builtins.deepSeq (furnish.compile {
      declarations = [ sample ];
      executors = [ invalidArtifactExecutor ];
      inherit ctx;
    }) true
  );

  # the emission site's argument shape is what decides which scopes it runs
  # under, so it is pinned here next to the counting it produces.
  programSlice =
    (import ../../program.nix {
      inherit lib resolve resolveSystem;
      # program's prepared door is not exercised here; the test resolver is
      # ctx-pure, so the prepared form is the same function.
      resolvePrepared = resolve;
      filePrincipals = _: [ ];
      hostUserNames = _: [ ];
    })
      { files = [ kittyEntry ]; };
  nixosArgs = builtins.functionArgs programSlice.nixos;

  # kitty's label carries brackets a store path cannot hold, and runtime names
  # the artifact after the destination.
  destinationNamedExecutor =
    (mkExecutor {
      identity = "executor/a";
      priority = 10;
    })
    // {
      materialize = declaration: {
        retainedArtifactTarget = builtins.path {
          path = declaration.source.value;
          name = "furnish-${baseNameOf declaration.filesystemIdentity.destination}";
        };
        cleanupStrategy = contract.strategies.exactSymlinkTarget;
        selfHealStrategy = contract.strategies.exactSymlinkTarget;
      };
    };

  compileKitty =
    declarations:
    furnish.compile {
      inherit declarations ctx;
      executors = [ destinationNamedExecutor ];
    };

  manifestKeys = builtins.attrNames sampleEntry;
  artifactTarget = sampleEntry.retainedArtifactTarget;
  manifestContext = builtins.getContext sampleResult.manifestJson;
  inherit (sampleResult) manifestDocument;

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
      name = "safe rendering never traverses arbitrary attribute values";
      pass =
        krisis.safeRender poisonSecret == "<unrenderable value>"
        && krisis.safeRender poisonType == "<unrenderable value>"
        && krisis.safeShape poisonType == "{ token, type }";
    }
    {
      name = "safe rendering tolerates poisoned derivation names";
      pass =
        krisis.safeRender poisonNamedDerivation == "<derivation ?>"
        && krisis.safeShape poisonNamedDerivation == "<derivation ?>";
    }
    {
      name = "safe rendering keeps flat scalar lists and rejects unsafe list members";
      pass =
        krisis.safeRender [
          "visible"
          1
          true
          null
        ] == ''["visible",1,true,null]''
        && krisis.safeRender poisonList == "<unrenderable value>";
    }
    {
      name = "sample manifest is byte-stable and entry order is canonical";
      pass =
        sampleResult.manifestJson == (compile [ sample ]).manifestJson
        && sampleResult.manifestPath == null
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
            "onConflict"
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
      name = "a declaration naming no conflict policy still serializes the error policy";
      pass = !(sample ? onConflict) && sampleEntry.onConflict == contract.conflictPolicies.error;
    }
    {
      name = "an explicit conflict policy reaches the manifest entry unchanged";
      pass = explicitPolicyEntry.onConflict == contract.conflictPolicies.sourceWins;
    }
    {
      name = "a conflict policy outside the enum is refused by shape validation";
      pass = throws (furnish.core.validateShape bogusPolicy);
    }
    {
      name = "shape validation accumulates metadata errors without forcing source value";
      pass =
        malformedShapeResult.success
        && builtins.length malformedShapeDiagnostics >= 8
        && builtins.elem "shape-validation/label-type" malformedShapeCodes
        && builtins.elem "shape-validation/authority-identity" malformedShapeCodes
        && builtins.elem "shape-validation/on-conflict-value" malformedShapeCodes;
    }
    {
      name = "executor metadata validation rejects malformed records before selection";
      pass = !malformedExecutorResult.success;
    }
    {
      name = "selected executor artifacts must satisfy the lifecycle result contract";
      pass = !invalidArtifactResult.success;
    }
    {
      name = "manifest document versions runtime diagnostics and carries entries";
      pass =
        manifestDocument.schemaVersion == contract.schemaVersion
        && manifestDocument.diagnosticContract == contract.runtimeDiagnostics
        && manifestDocument.entries == sampleResult.manifestData
        && contract.runtimeDiagnostics.schemaVersion == contract.diagnosticSchemaVersion
        && builtins.all builtins.isString (builtins.attrValues contract.runtimeDiagnostics.codes);
    }
    {
      name = "native executor tuple is exact and has no fallback identity";
      pass =
        contract.executors.nativeSymlink == {
          identity = "furnish/native-symlink";
          protocolVersion = 1;
          representation = contract.capabilities.symlink;
        };
    }
    {
      name = "manifest context pins a dedicated artifact object";
      pass =
        lib.hasPrefix "/nix/store/" artifactTarget
        && artifactTarget != toString ../default.nix
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
      name = "throwing provider callbacks fail through the furnish selection context";
      pass = throws (
        furnish.core.compile {
          declarations = [ sample ];
          inherit executors ctx;
          provider.selectApplicable = _declarations: _ctx: throw "boom, provider selection failed";
        }
      );
    }
    {
      name = "throwing executor callbacks fail through declaration and executor context";
      pass = throws (
        furnish.compile {
          declarations = [ sample ];
          executors = [
            (
              preferredExecutor
              // {
                identity = "executor/evil";
                materialize = _declaration: throw "boom, materialization failed";
              }
            )
          ];
          inherit ctx;
        }
      );
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
        && noOp.manifestDocument.entries == [ ]
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
      name = "lexical normalization collapses equivalent in-root spellings";
      pass =
        (furnish.core.deriveDestination canonicalSpelling).filesystemIdentity.canonical
        == "x86_64-linux/khion:/tmp/furnish/shared.conf";
    }
    {
      name = "lexical normalization still rejects managed-root escape";
      pass = throws (furnish.core.deriveDestination escaping);
    }
    {
      name = "single claims across principals build one deterministic host index";
      pass =
        builtins.attrNames (
          furnish.core.buildHostIndex {
            declarations = [
              userClaim
              (systemClaim // { destination = "furnish/system.conf"; })
              inactiveHostClaim
            ];
            principals = hostPrincipals;
          }
        ) == [
          "x86_64-linux/khion:/tmp/furnish/shared.conf"
          "x86_64-linux/khion:/tmp/furnish/system.conf"
        ];
    }
    {
      name = "cross-principal and same-principal collisions share one diagnostic";
      pass =
        crossCollisionText == expectedCrossCollisionText
        && samePrincipalCollisionText == expectedSamePrincipalCollisionText
        && throws (
          furnish.core.buildHostIndex {
            declarations = [
              userClaim
              systemClaim
            ];
            principals = hostPrincipals;
          }
        )
        && throws (compile [
          userClaim
          secondUserClaim
        ]);
    }
    {
      name = "three claimants are all rendered in deterministic order";
      pass =
        lib.hasInfix "system/x86_64-linux/khion (system-claim at system-source.nix)" threeClaimantText
        && lib.hasInfix "user/feltfomo (second-user-claim at second-user-source.nix)" threeClaimantText
        && lib.hasInfix "user/feltfomo (user-claim at user-source.nix)" threeClaimantText;
    }
    {
      name = "distinct collisions aggregate into one rendered report";
      pass =
        builtins.length (
          furnish.core.collisionDiagnostics (projectHost [
            userClaim
            systemClaim
            secondCollisionUser
            secondCollisionSystem
          ])
        ) == 2
        && lib.hasInfix "/tmp/furnish/other.conf" aggregateCollisionText
        && lib.hasInfix "/tmp/furnish/shared.conf" aggregateCollisionText;
    }
    {
      name = "whole host index stays payload executor generator and exclusion lazy";
      pass =
        (builtins.tryEval (
          builtins.deepSeq (furnish.core.buildHostIndex {
            declarations = [
              userClaim
              inactiveHostClaim
            ];
            principals = hostPrincipals;
          }) true
        )).success;
    }
    {
      name = "empty host index is inert";
      pass = furnish.core.buildHostIndex { principals = hostPrincipals; } == { };
    }
    {
      name = "the files layer generates the record kitty wrote by hand";
      pass = kittyGenerated == [ kittyRecord ];
    }
    {
      name = "a home-relative entry takes no declaration from a system principal";
      pass = systemOnlyGenerated == [ ];
    }
    {
      name = "hand-written and generated kitty records compile to one manifest";
      pass = (compileKitty [ kittyRecord ]).manifestJson == (compileKitty kittyGenerated).manifestJson;
    }
    {
      name = "the files layer takes no claim key and counts one declaration per principal handed in";
      pass =
        builtins.length (
          furnish.files.mkDeclarations {
            filesystemNamespace = "x86_64-linux/khion";
            principals = hostPrincipals;
            files = [
              kittyEntry
              (kittyEntry // { dest = ".config/kitty/other.conf"; })
            ];
          }
        ) == 2
        && builtins.length twoUserGenerated == 2;
    }
    {
      name = "one entry and one user principal make exactly one declaration";
      pass =
        furnish.files.mkDeclarations {
          filesystemNamespace = "x86_64-linux/khion";
          principals = [ userPrincipal ];
          files = [ kittyEntry ];
        } == [ kittyRecord ];
    }
    {
      name = "two user principals do not collapse onto one declaration";
      pass =
        map (declaration: declaration.authority.identity) twoUserGenerated == [
          "feltfomo"
          "grandpa"
        ]
        &&
          map (declaration: declaration.managedRoot) twoUserGenerated == [
            "/home/feltfomo"
            "/home/grandpa"
          ]
        && builtins.all (declaration: declaration.destination == kittyEntry.dest) twoUserGenerated;
    }
    {
      name = "an explicit principal managed root overrides the conventional home";
      pass = (builtins.head rootedUserGenerated).managedRoot == "/srv/furnish/feltfomo";
    }
    {
      name = "no principal at all is a host-scope zero, not the same zero as a system principal";
      pass = noPrincipalGenerated == [ ] && systemOnlyGenerated == [ ];
    }
    {
      name = "the emission site names host and user with defaults so the class wrapper keeps it";
      pass = nixosArgs.host && nixosArgs.user;
    }
    {
      name = "an empty file half generates an empty declaration set";
      pass =
        furnish.files.mkDeclarations {
          filesystemNamespace = "x86_64-linux/khion";
          principals = hostPrincipals;
        } == [ ];
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
    collisionEvidence
    ;
}
