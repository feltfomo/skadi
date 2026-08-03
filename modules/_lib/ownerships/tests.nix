# _lib/ownerships/tests.nix
#
# pure test gate for the engine. nothing else consumes the engine yet, so this is
# what proves it works, the three outcomes, a nested resolve, a throwaway third
# axis composing with no core edit, an opt-in merge strategy registering with no
# core edit, and the top identity law per axis. ownerships-check.nix forces `ok`
# under `nix flake check`.
{ lib }:
let
  engine = import ./engine.nix { inherit lib; };
  axes = import ./axes.nix { inherit lib; };
  merge = import ./merge.nix { inherit lib; };
  importUnitTests = import ./import-units-tests.nix { inherit lib; };
  krisis = import ../krisis { inherit lib; };

  inherit (axes)
    include
    exclude
    global
    mkSetAxis
    predicateAxis
    ;
  inherit (krisis) safeRender safeShape;

  # stubbed roster -- the real den-backed one replaces this later.
  registry = axes.registry {
    hosts = [
      "khion"
      "lumi"
    ];
    users = [
      "feltfomo"
      "grandpa"
    ];
  };

  defaultMerge = (merge.mkMerge { }).mergeTracked;

  ctx = {
    host = {
      name = "khion";
      # bare stub members ("khion"), so bind the ctx host's canonical id to the
      # same bare name; the generic memberOf then selects it without deriving a
      # system prefix this stub registry never uses.
      id = "khion";
    };
    user = {
      name = "feltfomo";
    };
  };

  resolve =
    args: unit:
    engine.resolve (
      {
        inherit registry;
        merge = defaultMerge;
        inherit ctx;
      }
      // args
    ) unit;

  # did forcing this value throw? deepSeq drives the lazy check/merge throws so
  # tryEval actually catches the impossible/conflict cases.
  throws = x: !(builtins.tryEval (builtins.deepSeq x x)).success;

  # frozen pre-registry membership check. this is the migration oracle, the
  # generic relation checker must match it exactly, including diagnostics.
  inherit (builtins) elem;
  inherit (builtins) filter;
  isGlobal = v: v.tag == "exclude" && v.set == [ ];
  inter = a: b: filter (x: elem x b) a;
  diff = a: b: filter (x: !(elem x b)) a;
  resolveMembers = members: v: if v.tag == "include" then inter v.set members else diff members v.set;
  legacyMembershipCheck =
    {
      hosts ? [ ],
      users ? [ ],
      membership ? { },
      usersWithUnknownMembership ? [ ],
    }:
    _registry: leaf:
    let
      hostClaim = leaf.claim.host;
      userClaim = leaf.claim.user;
      hs = resolveMembers hosts hostClaim;
      us = resolveMembers users userClaim;
      rescued = builtins.any (u: elem u usersWithUnknownMembership) us;
      pairs = builtins.any (h: builtins.any (u: elem u (membership.${h} or [ ])) us) hs;
    in
    if isGlobal hostClaim || isGlobal userClaim || hs == [ ] || us == [ ] || rescued || pairs then
      [ ]
    else
      [
        {
          kind = "impossible";
          unit = leaf.value;
          label = leaf.label or null;
          source = leaf.source or null;
          axes = [
            "host"
            "user"
          ];
          claims = leaf.claim;
          reason = "no user in { ${builtins.concatStringsSep ", " us} } lives on any host in { ${builtins.concatStringsSep ", " hs} } -- this host/user co-ownership can never apply";
        }
      ];

  # the meet law suite runs over a small closed universe, not sampled -- narrow
  # and top touch no roster, so exhaustive is cheap and actually proves the
  # laws instead of hoping a handful of samples happened to cover what matters.
  lawUniverse = [
    "a"
    "b"
    "c"
  ];
  subsetsOf =
    xs:
    if xs == [ ] then
      [ [ ] ]
    else
      let
        rest = subsetsOf (builtins.tail xs);
      in
      rest ++ map (s: [ (builtins.head xs) ] ++ s) rest;
  # every polarity value over the universe, both tags and every subset.
  lawValues = builtins.concatMap (s: [
    (include s)
    (exclude s)
  ]) (subsetsOf lawUniverse);
  # a throwaway axis just to reach `narrow` (== meet) and `top` -- narrow is
  # roster-independent, so which members this axis carries never matters here.
  lawAxis = mkSetAxis {
    key = "law";
    members = lawUniverse;
  };
  # `.set` is a set, not an ordered list -- exclude/exclude narrowing unions it
  # via ++, which can reorder. sort before comparing so the laws test the
  # value, not the union's incidental order.
  canon = v: v // { set = builtins.sort (a: b: a < b) v.set; };
  eqPolarity = a: b: canon a == canon b;

  # laziness and secret guard fixtures use values whose unsafe fields throw if
  # actually forced, standing in for a package or a secret that isn't
  # available at eval time. safeRender/safeShape must identify these by shape
  # alone and never touch the throwing fields.
  poisonDerivation = {
    type = "derivation";
    name = "poison-pkg";
    drvPath = throw "forced a derivation-shaped value";
    outPath = throw "forced a derivation-shaped value";
  };
  poisonSecret = {
    token = throw "forced a secret-shaped value";
  };

  # golden-error test crafts two leaves directly (no compose, no throw), so
  # the assertion pins exactly what an author sees on screen -- header count,
  # per-diagnostic bullet, the unit-identification branch (label vs unlabeled +
  # safeShape), and the axis/claim detail -- and proves the unlabeled branch
  # never renders the leaf's real (poison) value, only its safe shape. the
  # claim fragment below is rendered through the same toPretty call renderDiags
  # itself uses -- that's a trusted formatting primitive, not the logic under
  # test, so pinning it this way still exercises every line renderDiags/
  # renderDiag/identifyUnit actually own.
  goldenLeafUnlabeled = {
    claim = {
      host = include [ ];
      user = global;
    };
    value = poisonDerivation;
  };
  goldenLeafLabeled = {
    claim = {
      host = global;
      user = include [ "nobody" ];
    };
    value = poisonSecret;
    label = "my-labeled-unit";
  };
  goldenDiags =
    engine.satisfiableCheck registry goldenLeafUnlabeled
    ++ engine.satisfiableCheck registry goldenLeafLabeled;
  prettyClaim = c: lib.generators.toPretty { multiline = false; } c;
  goldenExpected =
    "ownerships: 2 ownership error(s):\n"
    + "  - unlabeled unit ${safeShape poisonDerivation}: axis 'host' claim can never be satisfied (disjoint nest or unknown name) (axis 'host', claim ${prettyClaim goldenLeafUnlabeled.claim})"
    + "\n"
    + "  - unit 'my-labeled-unit': axis 'user' claim can never be satisfied (disjoint nest or unknown name) (axis 'user', claim ${prettyClaim goldenLeafLabeled.claim})";

  relationRoster = {
    hosts = [
      "khion"
      "lumi"
      "server"
    ];
    users = [
      "feltfomo"
      "grandpa"
      "nomad"
      "ghostless"
    ];
    membership = {
      khion = [ "feltfomo" ];
      lumi = [
        "feltfomo"
        "grandpa"
      ];
      server = [ ];
    };
    usersWithUnknownMembership = [ "nomad" ];
  };
  relationRegistry = axes.registry {
    inherit (relationRoster) hosts users;
  };
  hostUserRelation = builtins.head (axes.relationsFor axes.relations relationRoster);
  relationCheck = engine.mkRelationCheck hostUserRelation;
  legacyRelationCheck = legacyMembershipCheck relationRoster;
  relationLeaf = hostClaim: userClaim: {
    claim = {
      host = hostClaim;
      user = userClaim;
    };
    value = poisonSecret;
  };
  relationMatrix = [
    {
      name = "known compatible";
      leaf = relationLeaf (include [ "khion" ]) (include [ "feltfomo" ]);
    }
    {
      name = "known none";
      leaf = (relationLeaf (include [ "khion" ]) (include [ "grandpa" ])) // {
        label = "known-none";
        source = "modules/example.nix";
        value.marker = "known-none";
      };
    }
    {
      name = "one unknown rescues a known incompatible member";
      leaf = relationLeaf (include [ "khion" ]) (include [
        "nomad"
        "grandpa"
      ]);
    }
    {
      name = "global host side";
      leaf = relationLeaf global (include [ "grandpa" ]);
    }
    {
      name = "global user side";
      leaf = relationLeaf (include [ "server" ]) global;
    }
    {
      name = "empty host side";
      leaf = relationLeaf (include [ "nobody" ]) (include [ "grandpa" ]);
    }
    {
      name = "empty user side";
      leaf = relationLeaf (include [ "khion" ]) (include [ "nobody" ]);
    }
    {
      name = "multi-member existential compatibility";
      leaf =
        relationLeaf
          (include [
            "khion"
            "server"
          ])
          (include [
            "grandpa"
            "feltfomo"
          ]);
    }
  ];
  knownNoneLeaf = (builtins.elemAt relationMatrix 1).leaf;
  knownNoneExpected = {
    kind = "impossible";
    unit = knownNoneLeaf.value;
    label = "known-none";
    source = "modules/example.nix";
    axes = [
      "host"
      "user"
    ];
    claims = knownNoneLeaf.claim;
    reason = "no user in { grandpa } lives on any host in { khion } -- this host/user co-ownership can never apply";
  };
  knownNoneRendered =
    "ownerships: 1 ownership error(s):\n"
    + "  - unit 'known-none': ${knownNoneExpected.reason} (axes host, user, claim ${
        lib.generators.toPretty { multiline = false; } knownNoneLeaf.claim
      })";

  stageRegistry = axes.registry {
    hosts = [
      "khion"
      "lumi"
      "vm"
    ];
    users = [
      "feltfomo"
      "grandpa"
    ];
  };

  # a greeter claimed for vm is invalid for the fleet even while another host
  # is building, so this rule consumes the composed tree before selection.
  greeterNeverOnVm = {
    view = "tree";
    run =
      { registry, leaves }:
      map
        (leaf: {
          kind = "impossible";
          unit = leaf.value;
          label = leaf.label or null;
          source = leaf.source or null;
          reason = "a greeter cannot be owned by vm";
        })
        (
          builtins.filter (
            leaf:
            leaf.value.greeter or false
            && builtins.elem "vm" (registry.host.observe leaf.claim.host).materializedMembers
          ) leaves
        );
  };

  # coverage is about this build, not the fleet declaration. only selected
  # leaves can provide its one bootloader.
  exactlyOneBootloader = {
    view = "survivors";
    run =
      { survivors, ... }:
      let
        bootloaders = builtins.filter (leaf: leaf.value.bootloader or false) survivors;
      in
      lib.optional (builtins.length bootloaders != 1) {
        kind = "coverage";
        unit = { };
        label = "bootloader coverage";
        reason = "this build must have exactly one bootloader survivor";
      };
  };

  stageArgs = {
    registry = stageRegistry;
    inherit ctx;
    merge = defaultMerge;
    stages = [
      greeterNeverOnVm
      exactlyOneBootloader
    ];
  };

  mkOrderedDiagnosticStage = view: reason: {
    inherit view;
    run = _args: [
      {
        kind = "test";
        unit = { };
        label = "diagnostic ordering";
        inherit reason;
      }
    ];
  };

  orderedTreeStages = [
    (mkOrderedDiagnosticStage "tree" "first tree diagnostic")
    (mkOrderedDiagnosticStage "survivors" "later survivor diagnostic")
    (mkOrderedDiagnosticStage "tree" "second tree diagnostic")
  ];

  safeStageSet = [
    {
      view = "leaf";
      run = _registry: leaf: builtins.seq (safeShape leaf.value) [ ];
    }
    {
      view = "tree";
      run = { leaves, ... }: builtins.deepSeq (map (leaf: safeShape leaf.value) leaves) [ ];
    }
    {
      view = "survivors";
      run =
        { survivors, ... }:
        builtins.deepSeq (map (leaf: safeShape leaf.value) survivors) [ ];
    }
  ];

  cases = [
    {
      name = "registered host/user relation is byte-identical to the frozen membership check";
      pass =
        hostUserRelation.unknown.left == [ ]
        && hostUserRelation.unknown.right == [ "nomad" ]
        && lib.all (
          entry: relationCheck relationRegistry entry.leaf == legacyRelationCheck relationRegistry entry.leaf
        ) relationMatrix;
    }
    {
      name = "registered relation pins the exact known-none diagnostic and rendered string";
      pass =
        relationCheck relationRegistry knownNoneLeaf == [ knownNoneExpected ]
        &&
          knownNoneExpected.reason
          == "no user in { grandpa } lives on any host in { khion } -- this host/user co-ownership can never apply"
        && engine.renderDiags [ knownNoneExpected ] == knownNoneRendered;
    }
    {
      name = "relation diagnostics identify a poison-carrying leaf without forcing its payload";
      pass =
        let
          leaf = relationLeaf (include [ "khion" ]) (include [ "grandpa" ]);
          rendered = engine.renderDiags (relationCheck relationRegistry leaf);
        in
        (builtins.tryEval (builtins.deepSeq rendered rendered)).success;
    }
    {
      name = "pre-select tree validity rejects a greeter claimed for vm before selection";
      pass = throws (
        engine.resolve stageArgs {
          label = "vm greeter";
          claim.host = include [ "vm" ];
          value.greeter = true;
        }
      );
    }

    {
      name = "post-select coverage ignores an inactive bootloader";
      pass = throws (
        engine.resolve stageArgs {
          claim.host = include [ "lumi" ];
          value.bootloader = true;
        }
      );
    }

    {
      name = "post-select coverage accepts exactly one active bootloader";
      pass =
        engine.resolve stageArgs {
          claim.host = include [ "khion" ];
          value.bootloader = true;
        } == {
          bootloader = true;
        };
    }

    {
      name = "tree diagnostics aggregate in registration order independent of cross-view list position";
      pass =
        map (diagnostic: diagnostic.reason) (
          engine.stageDiagnostics "tree" orderedTreeStages {
            registry = stageRegistry;
            leaves = [ ];
          }
        ) == [
          "first tree diagnostic"
          "second tree diagnostic"
        ];
    }

    {
      name = "an unknown stage view throws instead of silently failing open";
      pass = throws (
        engine.resolve {
          inherit registry ctx;
          merge = defaultMerge;
          stages = [
            {
              view = "survivior";
              run = _args: [ ];
            }
          ];
        } { value.x = 1; }
      );
    }

    {
      name = "all stage views and their trace reports preserve payload laziness";
      pass =
        let
          unit.value = {
            pkg = poisonDerivation;
            secret = poisonSecret;
          };
          args = {
            inherit registry ctx;
            merge = defaultMerge;
            stages = safeStageSet;
          };
          plain = engine.resolve args unit;
          traced = engine.trace args unit;
          observed = {
            plainKeys = builtins.attrNames plain;
            tracedKeys = builtins.attrNames traced.value;
            inherit (traced) stageReports;
          };
        in
        (builtins.tryEval (builtins.deepSeq observed observed)).success
        &&
          observed.plainKeys == [
            "pkg"
            "secret"
          ]
        && observed.tracedKeys == observed.plainKeys
        && map (report: report.view) observed.stageReports.leaf == [ "leaf" ]
        && map (report: report.view) observed.stageReports.tree == [ "tree" ]
        && map (report: report.view) observed.stageReports.survivors == [ "survivors" ];
    }
    {
      name = "host+user nest resolves";
      pass =
        resolve { } {
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
      name = "third axis (role) composes with no core change";
      pass =
        engine.resolve
          {
            registry = registry // {
              role = mkSetAxis {
                key = "role";
                members = [
                  "laptop"
                  "desktop"
                ];
              };
            };
            merge = defaultMerge;
            ctx = ctx // {
              role = {
                name = "desktop";
              };
            };
          }
          {
            claim.role = include [ "desktop" ];
            value.enable = true;
          } == {
          enable = true;
        };
    }

    {
      name = "disjoint nest -> impossible";
      pass = throws (
        resolve { } {
          claim.host = include [ "khion" ];
          children = [
            {
              claim.host = include [ "lumi" ];
              value.x = 1;
            }
          ];
        }
      );
    }

    {
      name = "nested blocks merge";
      pass =
        resolve { } {
          children = [
            {
              value = {
                a.b = [ 1 ];
                c = "keep";
              };
            }
            {
              value = {
                a.b = [ 2 ];
                d = "also";
              };
            }
          ];
        } == {
          a.b = [
            1
            2
          ];
          c = "keep";
          d = "also";
        };
    }

    {
      name = "scalar clash -> conflict";
      pass = throws (
        resolve { } {
          children = [
            { value.port = 80; }
            { value.port = 443; }
          ];
        }
      );
    }

    {
      name = "tracked merge preserves unlocked values and nested attr/list contributors";
      pass =
        let
          merger = merge.mkMerge { };
          contributor = identity: owners: { inherit identity owners; };
          ownersA = {
            host = include [ "khion" ];
            user = global;
          };
          ownersB = {
            host = global;
            user = include [ "feltfomo" ];
          };
          values = [
            {
              scalar = "same";
              nest = {
                attrs.left = 1;
                items = [ 1 ];
              };
            }
            {
              scalar = "same";
              nest = {
                attrs.right = 2;
                items = [ 2 ];
              };
            }
          ];
          entries = [
            {
              value = builtins.elemAt values 0;
              contributor = contributor "unit 'a'" ownersA;
            }
            {
              value = builtins.elemAt values 1;
              contributor = contributor "unit 'b'" ownersB;
            }
          ];
          merged = merger.mergeTracked entries;
          provenance = merged.provenance.children;
          identities = xs: map (x: x.identity) xs;
        in
        merged.value == merger.mergeAll values
        &&
          identities provenance.scalar.contributors == [
            "unit 'a'"
            "unit 'b'"
          ]
        && identities provenance.nest.children.attrs.children.left.contributors == [ "unit 'a'" ]
        && (builtins.head provenance.nest.children.attrs.children.left.contributors).owners == ownersA
        && identities provenance.nest.children.attrs.children.right.contributors == [ "unit 'b'" ]
        &&
          identities provenance.nest.children.items.contributors == [
            "unit 'a'"
            "unit 'b'"
          ]
        && (builtins.head provenance.nest.children.items.contributors).owners == ownersA
        && (builtins.elemAt provenance.nest.children.items.contributors 1).owners == ownersB;
    }

    {
      name = "tracked scalar conflict policy receives both contributing units";
      pass =
        let
          merger = merge.mkMerge {
            conflictPolicy =
              _path: _a: b:
              b.value;
          };
          merged = merger.mergeTracked [
            {
              value.port = 80;
              contributor = {
                identity = "unit 'a'";
                owners.host = include [ "khion" ];
              };
            }
            {
              value.port = 443;
              contributor = {
                identity = "unit 'b'";
                owners.host = global;
              };
            }
          ];
        in
        merged.value.port == 443
        &&
          map (x: x.identity) merged.provenance.children.port.contributors == [
            "unit 'a'"
            "unit 'b'"
          ];
    }

    {
      name = "ordinary resolve leaves merge provenance unforced";
      pass =
        let
          args = {
            inherit registry ctx;
            merge = defaultMerge;
          };
          unit = {
            label = throw "forced provenance identity";
            value.nested.answer = 42;
          };
          plain = engine.resolve args unit;
          traced = engine.trace args unit;
        in
        plain == { nested.answer = 42; } && throws traced.mergeProvenance;
    }

    {
      name = "single-writer lock accepts its declared writer";
      pass =
        let
          merger = merge.mkMerge {
            lockFor = path: if path == "port" then contributor: contributor.identity == "unit 'a'" else null;
          };
          merged = merger.mergeTracked [
            {
              value.port = 80;
              contributor = {
                identity = "unit 'a'";
                owners.host = include [ "khion" ];
              };
            }
          ];
        in
        merged.value == {
          port = 80;
        };
    }

    {
      name = "single-writer lock rejects an equal foreign write before scalar equality";
      pass =
        let
          merger = merge.mkMerge {
            lockFor = path: if path == "port" then contributor: contributor.identity == "unit 'a'" else null;
            conflictPolicy =
              _path: _a: _b:
              throw "lock authorization reached conflict policy";
          };
        in
        throws
          (merger.mergeTracked [
            {
              value.port = 80;
              contributor = {
                identity = "unit 'a'";
                owners.host = include [ "khion" ];
              };
            }
            {
              value.port = 80;
              contributor = {
                identity = "unit 'b'";
                owners.host = global;
              };
            }
          ]).value;
    }

    {
      name = "single-writer lock applies the caller's subtree predicate to descendants";
      pass =
        let
          merger = merge.mkMerge {
            lockFor =
              path:
              if path == "services.foo" || lib.hasPrefix "services.foo." path then
                contributor: contributor.identity == "unit 'a'"
              else
                null;
          };
        in
        throws
          (merger.mergeTracked [
            {
              value.services.foo.bar = true;
              contributor = {
                identity = "unit 'b'";
                owners.host = global;
              };
            }
          ]).value;
    }

    {
      name = "default merge doesn't force contributor identity or owners";
      pass =
        let
          merged = (merge.mkMerge { }).mergeTracked [
            {
              value.answer = 42;
              contributor = {
                identity = throw "forced default-path identity";
                owners = throw "forced default-path owners";
              };
            }
          ];
        in
        merged.value == { answer = 42; } && throws merged.provenance;
    }

    {
      name = "golden attributed conflict and lock diagnostics name safe identities, not values";
      pass =
        let
          a = {
            identity = "unit 'a'";
            owners.host = include [ "khion" ];
          };
          b = {
            identity = "unit 'b'";
            owners.host = global;
          };
        in
        merge.renderConflict "port" [
          a
          b
        ] == "ownerships: conflict at port: co-owners \"unit 'a'\", \"unit 'b'\" set differing values"
        &&
          merge.renderLockViolation "port" b
          == "ownerships: single-writer lock violation at port: foreign contributor \"unit 'b'\""
        && throws (
          resolve { } {
            children = [
              {
                label = "a";
                value.port = 80;
              }
              {
                label = "b";
                value.port = 443;
              }
            ];
          }
        );
    }

    {
      name = "merge trace attributes every nested path and keeps lists terminal";
      pass =
        let
          traced =
            engine.trace
              {
                inherit registry ctx;
                merge = defaultMerge;
              }
              {
                children = [
                  {
                    label = "global";
                    value = {
                      common = true;
                      services.foo.items = [ 1 ];
                    };
                  }
                  {
                    label = "narrowed";
                    claim.host = include [ "khion" ];
                    value = {
                      common = true;
                      services.foo.items = [ 2 ];
                    };
                  }
                ];
              };
          provenance = traced.mergeProvenance;
          identities = contributors: map (contributor: contributor.identity) contributors;
          items = provenance.children.services.children.foo.children.items;
        in
        traced.value == {
          common = true;
          services.foo.items = [
            1
            2
          ];
        }
        && provenance.path == ""
        && provenance.children.services.path == "services"
        && provenance.children.services.children.foo.path == "services.foo"
        && items.path == "services.foo.items"
        && items.children == { }
        &&
          identities items.contributors == [
            "unit 'global'"
            "unit 'narrowed'"
          ]
        && (builtins.head items.contributors).owners.host == global
        && (builtins.elemAt items.contributors 1).owners.host == include [ "khion" ];
    }

    {
      name = "plain and trace pin the same rendered impossible diagnostic string";
      pass =
        let
          args = {
            inherit registry ctx;
            merge = defaultMerge;
          };
          unit = {
            label = "unknown-host";
            claim.host = include [ "nobody" ];
            value.x = 1;
          };
          leaves = engine.compose registry unit;
          plainRendered = engine.renderDiags (
            engine.stageDiagnostics "leaf" engine.defaultStages {
              inherit registry leaves;
            }
          );
          traceRendered = (engine.trace args unit).diagnosticText.leaf;
        in
        plainRendered == traceRendered
        && throws (engine.resolve args unit)
        && throws (engine.trace args unit);
    }

    {
      name = "inactive leaf drops silently";
      pass =
        resolve { } {
          children = [
            { value.shared = true; }
            {
              claim.host = include [ "lumi" ];
              value.lumiOnly = true;
            }
          ];
        } == {
          shared = true;
        };
    }

    {
      name = "dedup-union opt-in strategy registers";
      pass =
        engine.resolve
          {
            inherit registry ctx;
            merge =
              (merge.mkMerge {
                listStrategyFor = path: if path == "tags" then "dedup-union" else "ordered-concat";
              }).mergeTracked;
          }
          {
            children = [
              {
                value = {
                  tags = [
                    "x"
                    "y"
                  ];
                  log = [ 1 ];
                };
              }
              {
                value = {
                  tags = [
                    "y"
                    "z"
                  ];
                  log = [ 2 ];
                };
              }
            ];
          } == {
          tags = [
            "x"
            "y"
            "z"
          ];
          log = [
            1
            2
          ];
        };
    }

    {
      name = "top identity law per axis";
      pass =
        let
          samples = [
            (include [ "khion" ])
            (exclude [ "lumi" ])
            global
            (include [ ])
          ];
          law =
            axis:
            # a set axis's top is its global identity, so isTop must accept it;
            # the narrow identity law then holds for every sample around it.
            axis.isTop axis.top
            && lib.all (v: axis.narrow axis.top v == v && axis.narrow v axis.top == v) samples;
        in
        lib.all law [
          registry.host
          registry.user
          (mkSetAxis {
            key = "role";
            members = [ "laptop" ];
          })
        ];
    }

    {
      name = "polarity meet: identity law, exhaustive over {a,b,c}";
      pass = lib.all (
        v: eqPolarity (lawAxis.narrow lawAxis.top v) v && eqPolarity (lawAxis.narrow v lawAxis.top) v
      ) lawValues;
    }

    {
      name = "polarity meet: commutativity law, exhaustive over {a,b,c}";
      pass = lib.all (
        a: lib.all (b: eqPolarity (lawAxis.narrow a b) (lawAxis.narrow b a)) lawValues
      ) lawValues;
    }

    {
      name = "polarity meet: idempotence law, exhaustive over {a,b,c}";
      pass = lib.all (v: eqPolarity (lawAxis.narrow v v) v) lawValues;
    }

    {
      name = "polarity meet: associativity law, exhaustive over {a,b,c}";
      pass = lib.all (
        a:
        lib.all (
          b:
          lib.all (
            c: eqPolarity (lawAxis.narrow (lawAxis.narrow a b) c) (lawAxis.narrow a (lawAxis.narrow b c))
          ) lawValues
        ) lawValues
      ) lawValues;
    }

    {
      name = "ctx missing a set axis's key still throws when a claim narrows on it";
      pass = throws (
        engine.resolve
          {
            inherit registry;
            merge = defaultMerge;
            ctx = {
              host = {
                name = "khion";
              };
            };
          }
          {
            claim.user = include [ "feltfomo" ];
            value.x = 1;
          }
      );
    }

    {
      name = "untagged claim tolerates a null-or-absent ctx entity";
      pass =
        engine.resolve {
          inherit registry;
          merge = defaultMerge;
          # exactly what a bare program.nix caller passes -- keys present, null.
          ctx = {
            host = null;
            user = null;
          };
        } { value.x = 1; } == {
          x = 1;
        };
    }

    {
      name = "predicate axis needs no ctx entity of its own";
      pass =
        engine.resolve
          {
            registry = registry // {
              when = predicateAxis;
            };
            merge = defaultMerge;
            inherit ctx;
          }
          {
            claim.when = c: c.host.name == "khion";
            value.enable = true;
          } == {
          enable = true;
        };
    }

    {
      name = "host-narrowed claim resolves with the user entity explicitly null";
      pass =
        engine.resolve
          {
            inherit registry;
            merge = defaultMerge;
            # a host-only build has a real host and no user in scope. the user axis
            # stays global for this claim, so assertCtx never demands it and
            # select never reads it -- the null-user tolerance the system binding
            # rides on.
            ctx = {
              host = {
                name = "khion";
                id = "khion";
              };
              user = null;
            };
          }
          {
            claim.host = include [ "khion" ];
            value.x = 1;
          } == {
          x = 1;
        };
    }

    {
      name = "safeShape identifies a derivation by name, never touches its fields";
      pass = safeShape poisonDerivation == "<derivation poison-pkg>";
    }

    {
      name = "safeShape lists attribute names only, never forces their values";
      pass = safeShape poisonSecret == "{ token }";
    }

    {
      name = "safeRender identifies a derivation by name, never touches its fields";
      pass = safeRender poisonDerivation == "<derivation poison-pkg>";
    }

    {
      name = "safeRender falls back safely on a value that throws when serialized";
      pass = safeRender poisonSecret == "<unrenderable value>";
    }

    {
      name = "compose carries label/source as leaf-sibling fields; strip drops them before merge";
      pass =
        let
          leaves = engine.compose registry {
            label = "my-unit";
            source = "modules/foo.nix";
            value.x = 1;
          };
          leaf = builtins.head leaves;
        in
        leaf.label == "my-unit"
        && leaf.source == "modules/foo.nix"
        && engine.strip leaves == [ { x = 1; } ];
    }

    {
      name = "a leaf's label rides through compose without disrupting an impossible resolve";
      pass = throws (
        resolve { } {
          claim.host = include [ "khion" ];
          children = [
            {
              claim.host = include [ "lumi" ];
              label = "conflicting-unit";
              value.x = 1;
            }
          ];
        }
      );
    }

    {
      name = "impossible claim on a unit carrying a secret-shaped value still throws";
      pass = throws (
        resolve { } {
          claim.host = include [ "khion" ];
          children = [
            {
              claim.host = include [ "lumi" ];
              value = {
                secret = poisonSecret;
              };
            }
          ];
        }
      );
    }

    {
      name = "merge conflict between a plain value and a derivation-shaped value still throws";
      pass = throws (
        resolve { } {
          children = [
            { value.pkg = "not-a-package"; }
            { value.pkg = poisonDerivation; }
          ];
        }
      );
    }

    {
      name = "golden error: renderDiags exactly renders 2 diagnostics (unlabeled poison-carrying unit + labeled unit) without forcing either payload";
      pass =
        let
          rendered = engine.renderDiags goldenDiags;
        in
        builtins.length goldenDiags == 2
        && (builtins.tryEval (builtins.deepSeq rendered rendered)).success
        && rendered == goldenExpected;
    }

    {
      name = "trace and resolve share one selected output";
      pass =
        let
          unit = {
            claim.host = include [ "khion" ];
            value.answer = 42;
          };
          args = {
            inherit registry ctx;
            merge = defaultMerge;
          };
          traced = engine.trace args unit;
          leaf = builtins.head traced.trace;
        in
        traced.value == engine.resolve args unit
        && leaf.selected
        && leaf.axisResults.host.details.materializedMembers == [ "khion" ]
        && leaf.axisResults.host.decision == "selected";
    }

    {
      name = "trace observes names and value shape without forcing payload fields";
      pass =
        let
          unit = {
            claim.host = include [ "khion" ];
            value = {
              pkg = poisonDerivation;
              secret = poisonSecret;
            };
          };
          args = {
            inherit registry ctx;
            merge = defaultMerge;
          };
          plain = engine.resolve args unit;
          traced = engine.trace args unit;
          leaf = builtins.head traced.trace;
          observed = {
            plainKeys = builtins.attrNames plain;
            tracedKeys = builtins.attrNames traced.value;
            inherit (leaf)
              identity
              effectiveClaim
              selected
              rejectedBy
              checkResults
              ctxRequirements
              preMergeContribution
              ;
            inherit (leaf) axisResults;
          };
        in
        (builtins.tryEval (builtins.deepSeq observed observed)).success
        &&
          observed.plainKeys == [
            "pkg"
            "secret"
          ]
        && observed.tracedKeys == observed.plainKeys
        && observed.identity == "unlabeled unit { pkg, secret }"
        && observed.preMergeContribution.shape == "{ pkg, secret }"
        &&
          observed.preMergeContribution.offeredPaths == [
            "pkg"
            "secret"
          ]
        && observed.preMergeContribution.stage == "pre-merge"
        && observed.axisResults.host.details.materializedMembers == [ "khion" ]
        && observed.checkResults == [ ]
        &&
          observed.ctxRequirements.host == {
            key = "host";
            required = true;
            available = true;
          };
    }

    {
      name = "trace reports identity, context requirements, and the exact rejecting axis";
      pass =
        let
          args = {
            inherit registry ctx;
            merge = defaultMerge;
          };
          traced = engine.trace args {
            label = "lumi-only";
            claim.host = include [ "lumi" ];
            value.services.example.enable = true;
          };
          leaf = builtins.head traced.trace;
        in
        traced.value == { }
        && leaf.identity == "unit 'lumi-only'"
        && leaf.effectiveClaim.host == include [ "lumi" ]
        && leaf.checkResults == [ ]
        && leaf.ctxRequirements.host.required
        && leaf.ctxRequirements.host.available
        && !leaf.selected
        && leaf.rejectedBy == [ "host" ]
        && leaf.axisResults.host.decision == "rejected"
        && leaf.preMergeContribution == null;
    }

    {
      name = "predicate observation reports its decision without fabricated members";
      pass =
        let
          traced =
            engine.trace
              {
                registry = registry // {
                  when = predicateAxis;
                };
                merge = defaultMerge;
                inherit ctx;
              }
              {
                claim.when = c: c.host.name == "lumi";
                value.x = 1;
              };
          result = (builtins.head traced.trace).axisResults.when;
        in
        !result.selected && result.decision == "rejected" && !(result.details ? materializedMembers);
    }

    {
      name = "plain and traced impossible claims both preserve the error outcome";
      pass =
        let
          args = {
            inherit registry ctx;
            merge = defaultMerge;
          };
          unit = {
            claim.host = include [ "nobody" ];
            value.x = 1;
          };
        in
        throws (engine.resolve args unit) && throws (engine.trace args unit);
    }

    {
      name = "default merger remains strict ordered and keeps contributor shape";
      pass =
        let
          merger = merge.mkMerge { };
          entries = [
            {
              value = {
                tags = [ "a" ];
                port = 80;
              };
              contributor = {
                identity = "unit 'a'";
                owners = { };
              };
            }
            {
              value = {
                tags = [ "b" ];
                port = 80;
              };
              contributor = {
                identity = "unit 'b'";
                owners = { };
              };
            }
          ];
          merged = merger.mergeTracked entries;
          stripped = engine.stripForMerge [
            {
              claim = { };
              value.answer = 42;
            }
          ];
        in
        merged.value == {
          tags = [
            "a"
            "b"
          ];
          port = 80;
        }
        &&
          builtins.attrNames (builtins.head stripped).contributor == [
            "identity"
            "owners"
          ];
    }

    {
      name = "different unit profiles on disjoint attrs fall back to deep cleanly";
      pass =
        let
          merged = (merge.mkMerge { profiles = merge.builtinProfiles; }).mergeTracked [
            {
              value.left = 1;
              contributor = {
                identity = "unit 'left'";
                owners = { };
                mergeProfile = "last-wins";
              };
            }
            {
              value.right = 2;
              contributor = {
                identity = "unit 'right'";
                owners = { };
                mergeProfile = "strict-ordered";
              };
            }
          ];
        in
        merged.value == {
          left = 1;
          right = 2;
        };
    }

    {
      name = "unanimous last-wins units deep-merge disjoint attrs";
      pass =
        let
          merged = (merge.mkMerge { profiles = merge.builtinProfiles; }).mergeTracked [
            {
              value.left = 1;
              contributor = {
                identity = "unit 'left'";
                owners = { };
                mergeProfile = "last-wins";
              };
            }
            {
              value.right = 2;
              contributor = {
                identity = "unit 'right'";
                owners = { };
                mergeProfile = "last-wins";
              };
            }
          ];
        in
        merged.value == {
          left = 1;
          right = 2;
        };
    }

    {
      name = "different explicit profiles on one scalar throw loud";
      pass =
        throws
          ((merge.mkMerge { profiles = merge.builtinProfiles; }).mergeTracked [
            {
              value.port = 80;
              contributor = {
                identity = "unit 'a'";
                owners = { };
                mergeProfile = "last-wins";
              };
            }
            {
              value.port = 443;
              contributor = {
                identity = "unit 'b'";
                owners = { };
                mergeProfile = "strict-ordered";
              };
            }
          ]).value;
    }

    {
      name = "unanimous last-wins units select the right scalar";
      pass =
        let
          merged = (merge.mkMerge { profiles = merge.builtinProfiles; }).mergeTracked [
            {
              value.port = 80;
              contributor = {
                identity = "unit 'a'";
                owners = { };
                mergeProfile = "last-wins";
              };
            }
            {
              value.port = 443;
              contributor = {
                identity = "unit 'b'";
                owners = { };
                mergeProfile = "last-wins";
              };
            }
          ];
        in
        merged.value.port == 443;
    }

    {
      name = "one last-wins unit cannot override an unprofiled scalar co-owner";
      pass =
        throws
          ((merge.mkMerge { profiles = merge.builtinProfiles; }).mergeTracked [
            {
              value.port = 80;
              contributor = {
                identity = "unit 'a'";
                owners = { };
                mergeProfile = "last-wins";
              };
            }
            {
              value.port = 443;
              contributor = {
                identity = "unit 'b'";
                owners = { };
              };
            }
          ]).value;
    }

    {
      name = "one last-wins list contributor cannot silently merge with an unprofiled co-owner";
      pass =
        throws
          ((merge.mkMerge { profiles = merge.builtinProfiles; }).mergeTracked [
            {
              value.tags = [ "a" ];
              contributor = {
                identity = "unit 'a'";
                owners = { };
                mergeProfile = "last-wins";
              };
            }
            {
              value.tags = [ "b" ];
              contributor = {
                identity = "unit 'b'";
                owners = { };
              };
            }
          ]).value;
    }

    {
      name = "path profile is authoritative and isolated to its selected paths";
      pass =
        let
          merger = merge.mkMerge {
            profiles = merge.builtinProfiles;
            profileForPath = path: if path == "tags" then "last-wins" else null;
          };
          merged = merger.mergeTracked [
            {
              value = {
                tags = [ "old" ];
                log = [ 1 ];
                stable = true;
              };
              contributor = {
                identity = "unit 'a'";
                owners = { };
              };
            }
            {
              value = {
                tags = [ "new" ];
                log = [ 2 ];
                stable = true;
              };
              contributor = {
                identity = "unit 'b'";
                owners = { };
              };
            }
          ];
        in
        merged.value == {
          tags = [ "new" ];
          log = [
            1
            2
          ];
          stable = true;
        };
    }

    {
      name = "last-wins attrset treatment reuses the right tracked subtree";
      pass =
        let
          merger = merge.mkMerge {
            profiles = merge.builtinProfiles;
            profileForPath = path: if path == "service" then "last-wins" else null;
          };
          merged = merger.mergeTracked [
            {
              value.service = {
                port = 80;
                left = true;
              };
              contributor = {
                identity = "unit 'a'";
                owners = { };
              };
            }
            {
              value.service = {
                port = 443;
                right = true;
              };
              contributor = {
                identity = "unit 'b'";
                owners = { };
              };
            }
          ];
          serviceProvenance = merged.provenance.children.service;
        in
        merged.value.service == {
          port = 443;
          right = true;
        }
        &&
          map (contributor: contributor.identity) serviceProvenance.contributors == [
            "unit 'a'"
            "unit 'b'"
          ]
        &&
          builtins.attrNames serviceProvenance.children == [
            "port"
            "right"
          ];
    }

    {
      name = "unknown contributor and path profile names fail closed";
      pass =
        throws
          ((merge.mkMerge { profiles = merge.builtinProfiles; }).mergeTracked [
            {
              value.answer = 42;
              contributor = {
                identity = "unit 'bad'";
                owners = { };
                mergeProfile = "missing";
              };
            }
          ]).value
        &&
          throws
            (
              (merge.mkMerge {
                profiles = merge.builtinProfiles;
                profileForPath = path: if path == "port" then "missing" else null;
              }).mergeTracked
              [
                {
                  value.port = 80;
                  contributor = {
                    identity = "unit 'a'";
                    owners = { };
                  };
                }
                {
                  value.port = 443;
                  contributor = {
                    identity = "unit 'b'";
                    owners = { };
                  };
                }
              ]
            ).value;
    }

    {
      name = "lock authorization still precedes last-wins policy";
      pass =
        throws
          (
            (merge.mkMerge {
              profiles = merge.builtinProfiles;
              profileForPath = path: if path == "port" then "last-wins" else null;
              lockFor = path: if path == "port" then contributor: contributor.identity == "unit 'a'" else null;
            }).mergeTracked
            [
              {
                value.port = 80;
                contributor = {
                  identity = "unit 'a'";
                  owners = { };
                };
              }
              {
                value.port = 443;
                contributor = {
                  identity = "unit 'b'";
                  owners = { };
                };
              }
            ]
          ).value;
    }

    {
      name = "profiled merge doesn't force values, identity, or owners";
      pass =
        let
          merged = (merge.mkMerge { profiles = merge.builtinProfiles; }).mergeTracked [
            {
              value = {
                answer = 1;
                pkg = poisonDerivation;
              };
              contributor = {
                identity = throw "forced profiled identity";
                owners = throw "forced profiled owners";
                mergeProfile = "last-wins";
              };
            }
            {
              value = {
                answer = 2;
                secret = poisonSecret;
              };
              contributor = {
                identity = throw "forced profiled identity";
                owners = throw "forced profiled owners";
                mergeProfile = "last-wins";
              };
            }
          ];
          inherit (merged) value;
        in
        builtins.deepSeq value.answer (value.answer == 2)
        && builtins.deepSeq (builtins.attrNames value) (
          builtins.attrNames value == [
            "answer"
            "secret"
          ]
        );
    }

    {
      name = "profiled resolve keeps poison payloads and contributor metadata lazy";
      pass =
        let
          profiledMerge = (merge.mkMerge { profiles = merge.builtinProfiles; }).mergeTracked;
          value =
            engine.resolve
              {
                inherit registry ctx;
                merge = profiledMerge;
              }
              {
                children = [
                  {
                    label = throw "forced profiled resolve identity";
                    mergeProfile = "last-wins";
                    value = {
                      answer = 1;
                      pkg = poisonDerivation;
                    };
                  }
                  {
                    source = throw "forced profiled resolve identity";
                    mergeProfile = "last-wins";
                    value = {
                      answer = 2;
                      secret = poisonSecret;
                    };
                  }
                ];
              };
        in
        builtins.deepSeq value.answer (value.answer == 2)
        && builtins.deepSeq (builtins.attrNames value) (
          builtins.attrNames value == [
            "answer"
            "secret"
          ]
        );
    }
    {
      name = "equal derivations merge as terminal values";
      pass =
        let
          left = {
            type = "derivation";
            outPath = "/nix/store/ownerships-same";
            drvPath = throw "forced left derivation internals";
          };
          right = {
            type = "derivation";
            outPath = "/nix/store/ownerships-same";
            drvPath = throw "forced right derivation internals";
          };
          merged = (merge.mkMerge { }).mergeTwo "pkg" left right;
        in
        merged.outPath == left.outPath;
    }
    {
      name = "different derivations conflict without forcing their internals";
      pass =
        let
          left = {
            type = "derivation";
            outPath = "/nix/store/ownerships-left";
            drvPath = throw "forced left derivation internals";
          };
          right = {
            type = "derivation";
            outPath = "/nix/store/ownerships-right";
            drvPath = throw "forced right derivation internals";
          };
        in
        throws ((merge.mkMerge { }).mergeTwo "pkg" left right);
    }
    {
      name = "function-valued co-owners use the ownership conflict path";
      pass = throws ((merge.mkMerge { }).mergeTwo "handler" (_: 1) (_: 2));
    }
    {
      name = "stage validation rejects a missing or non-function callback";
      pass =
        throws (engine.check [ { view = "leaf"; } ] registry [ ])
        && throws (
          engine.check [
            {
              view = "tree";
              run = 1;
            }
          ] registry [ ]
        );
    }
    {
      name = "activated malformed merge profiles fail through ownerships validation";
      pass =
        let
          profiles = merge.builtinProfiles // {
            broken = {
              listStrategy = "ordered-concat";
              scalarPolicy = 1;
              attrsetTreatment = "deep";
            };
          };
          merged = (merge.mkMerge { inherit profiles; }).mergeTracked [
            {
              value.answer = 1;
              contributor = {
                identity = "broken-profile";
                owners = { };
                mergeProfile = "broken";
              };
            }
          ];
        in
        throws merged.value.answer;
    }
    {
      name = "unused malformed merge profile registrations stay lazy";
      pass =
        let
          profiles = merge.builtinProfiles // {
            broken = throw "forced an unused merge profile";
          };
          merged = (merge.mkMerge { inherit profiles; }).mergeTracked [
            {
              value.answer = 1;
              contributor = {
                identity = "plain";
                owners = { };
              };
            }
          ];
        in
        merged.value.answer == 1;
    }
    {
      name = "activated non-function list strategies fail before application";
      pass = throws (
        (merge.mkMerge {
          strategies = merge.builtinStrategies // {
            broken = 1;
          };
          listStrategyFor = _path: "broken";
        }).mergeTwo
          "items"
          [ 1 ]
          [ 2 ]
      );
    }
  ];

  failing = builtins.filter (c: !c.pass) cases;

  ok =
    if failing == [ ] && importUnitTests.ok then
      true
    else
      throw "ownerships tests FAILED: ${lib.concatMapStringsSep ", " (c: c.name) failing}";
in
{
  inherit cases ok;
}
