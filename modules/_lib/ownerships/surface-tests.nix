# _lib/ownerships/surface-tests.nix
#
# Proof for the authoring surface: throwaway aspects written the way a real one
# would be, resolved against a small fleet. `results` is the resolved output per
# claim kind, kept plain so it can be eyeballed with `nix eval`; `ok` asserts
# each and is what a flake check forces. Nothing den-related is imported, so a
# green run also proves the surface resolves standalone.
{ lib }:
let
  axes = import ./axes.nix { inherit lib; };
  resolveLib = import ./resolve.nix { inherit lib; };
  surface = import ./surface.nix { inherit lib; };
  inherit (surface)
    define
    toRoster
    mkResolve
    mkResolveSystem
    mkResolveTrace
    mkResolveSystemTrace
    mkResolveStrict
    mkResolveSystemStrict
    translate
    claimKeys
    ;

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
    # hosts = null (the default): unknown host membership, rescued through
    # the membership check the same way strict validation must rescue it.
    (define.user "nomad" { })
  ];

  resolve = mkResolve roster;
  resolveSystem = mkResolveSystem roster;
  resolveTrace = mkResolveTrace roster;
  resolveSystemTrace = mkResolveSystemTrace roster;
  resolveStrict = mkResolveStrict roster;
  resolveSystemStrict = mkResolveSystemStrict roster;

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

  # host-only (system-scope) ctx: a real host, no user -- what a nixos slice
  # resolves under. "vm" is a host outside the claim, standing in for the
  # headless installer-test VM the compositor must stay off.
  ctxSystemKhion = {
    host = {
      name = "khion";
    };
  };
  ctxSystemVm = {
    host = {
      name = "vm";
    };
  };

  # strict-mode ctx fixtures: a host outside the roster, a user outside the
  # roster, an impossible but individually-valid pair (grandpa lives on
  # lumi, not khion), and an unknown-membership user (nomad, hosts = null)
  # that strict validation must still rescue rather than reject.
  ctxUnknownHost = {
    host = {
      name = "ghost";
    };
    user = {
      name = "feltfomo";
    };
  };
  ctxUnknownUser = {
    host = {
      name = "khion";
    };
    user = {
      name = "nobody";
    };
  };
  ctxImpossiblePair = {
    host = {
      name = "khion";
    };
    user = {
      name = "grandpa";
    };
  };
  ctxRescuedUnknownMembership = {
    host = {
      name = "khion";
    };
    user = {
      name = "nomad";
    };
  };
  ctxSystemUnknownHost = {
    host = {
      name = "ghost";
    };
  };

  run =
    c: units:
    let
      plain = resolve units c;
      traced = resolveTrace units c;
    in
    assert traced.value == plain;
    plain;

  runSystem =
    c: units:
    let
      plain = resolveSystem units c;
      traced = resolveSystemTrace units c;
    in
    assert traced.value == plain;
    plain;

  hostMissTrace = resolveTrace [
    {
      hosts = [ "khion" ];
      pkg = "khion-only";
    }
  ] ctxLumi;
  whenMissTrace = resolveTrace [
    {
      when = { host, ... }: host.gpu == "nvidia";
      pkg = "nvidia-only";
    }
  ] ctxLumi;
  labeledTrace = resolveTrace [
    {
      label = "khion-only-unit";
      hosts = [ "khion" ];
      pkg = "khion-only";
    }
  ] ctx;

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

    # a unit's label is author-facing identification only -- it must never
    # change what gets merged.
    labeledUnit = run ctx [
      {
        label = "khion-only-unit";
        hosts = [ "khion" ];
        pkg = "khion-only";
      }
    ];

    # host-only system scope: a compositor-shaped unit owned by two hosts,
    # resolved with only a host in ctx (no user), plus the off-claim miss.
    systemHostHit = runSystem ctxSystemKhion [
      {
        hosts = [
          "khion"
          "lumi"
        ];
        programs.hyprland.enable = true;
      }
    ];
    systemHostMiss = runSystem ctxSystemVm [
      {
        hosts = [
          "khion"
          "lumi"
        ];
        programs.hyprland.enable = true;
      }
    ];

    # value escape hatch: users.* is both a claim key and a real NixOS option
    # path, so this is the motivating collision -- global (untagged), so it's
    # not run through a host/user claim at all.
    valueEscapeHatch = run ctx [
      {
        value = {
          users.users.alice = {
            isNormalUser = true;
          };
        };
      }
    ];

    # same payload, now narrowed by a host claim -- proves a claim still
    # narrows around a value block instead of being swallowed by it.
    valueEscapeHatchHit = run ctx [
      {
        hosts = [ "khion" ];
        value = {
          users.users.alice = {
            isNormalUser = true;
          };
        };
      }
    ];
    valueEscapeHatchMiss = run ctxLumi [
      {
        hosts = [ "khion" ];
        value = {
          users.users.alice = {
            isNormalUser = true;
          };
        };
      }
    ];

    # translate only intercepts a unit's own top-level keys -- reserved-looking
    # names sitting *inside* a value block are never re-scanned as claims, so
    # nothing here gets silently dropped despite the name collision.
    valueNoSwallow = run ctx [
      {
        value = {
          hosts = "not-a-claim-this-is-config";
          when = "also-just-a-string";
        };
      }
    ];

    # a value + children node must merge identically to the pre-existing
    # inline-config + children node above (`nested`) -- same claims, same
    # shape, config just routed through the hatch instead of inline.
    nestedViaValue = run ctx [
      {
        hosts = [
          "khion"
          "lumi"
        ];
        value = {
          packages = [ "base" ];
        };
        children = [
          {
            users = [ "feltfomo" ];
            value = {
              packages = [ "feltfomo-extra" ];
            };
          }
          {
            hosts = [ "khion" ];
            value = {
              services.hypridle.enable = true;
            };
          }
        ];
      }
    ];
  };

  # deepSeq drives the lazy check/merge throws so tryEval catches the impossible
  # case below.
  throws = x: !(builtins.tryEval (builtins.deepSeq x x)).success;

  defaultEngineArgs = resolveLib.engineArgsFor roster;
  projectedUserCtx = axes.contextFor defaultEngineArgs.registry (ctx // { unrelated = "private"; });
  projectedSystemCtx = axes.contextFor defaultEngineArgs.registry (
    ctxSystemKhion // { unrelated = "private"; }
  );

  checks = [
    {
      name = "default registry projects the byte-identical bounded user and system contexts";
      pass =
        projectedUserCtx == {
          inherit (ctx) host user;
        }
        &&
          projectedSystemCtx == {
            inherit (ctxSystemKhion) host;
            user = null;
          };
    }
    {
      name = "default descriptors preserve the public key, registry, and roster shapes";
      pass =
        claimKeys == [
          "hosts"
          "users"
          "exceptHosts"
          "exceptUsers"
          "when"
        ]
        &&
          builtins.attrNames defaultEngineArgs.registry == [
            "host"
            "user"
            "when"
          ]
        &&
          builtins.attrNames roster == [
            "hosts"
            "membership"
            "users"
            "usersWithUnknownMembership"
          ];
    }
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
      name = "label never leaks into merged output";
      pass = results.labeledUnit == { pkg = "khion-only"; };
    }
    {
      name = "label/source are optional plain-string identification, not claims or config";
      pass =
        translate {
          label = "my-unit";
          source = "modules/foo.nix";
          pkg = "x";
        } == {
          claim = { };
          value = {
            pkg = "x";
          };
          label = "my-unit";
          source = "modules/foo.nix";
        };
    }
    {
      name = "a non-string label throws at author time";
      pass = throws (translate {
        label = 123;
        pkg = "x";
      });
    }
    {
      name = "a non-string source throws at author time";
      pass = throws (translate {
        source = { };
        pkg = "x";
      });
    }
    {
      name = "label/source don't inherit to children";
      pass =
        let
          t = translate {
            label = "parent";
            pkg = "x";
            children = [ { pkg = "y"; } ];
          };
          child = builtins.head t.children;
        in
        t.label == "parent" && !(child ? label);
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
    {
      name = "system scope resolves a host-narrowed unit with no user bound";
      pass =
        results.systemHostHit == {
          programs.hyprland.enable = true;
        };
    }
    {
      name = "system scope drops a host-narrowed unit off its claimed hosts";
      pass = results.systemHostMiss == { };
    }
    {
      name = "system scope rejects a users claim at author time";
      pass = throws (
        resolveSystem [
          {
            hosts = [ "khion" ];
            users = [ "feltfomo" ];
            programs.hyprland.enable = true;
          }
        ] ctxSystemKhion
      );
    }
    {
      name = "system scope rejects an exceptUsers claim at author time";
      pass = throws (
        resolveSystem [
          {
            exceptUsers = [ "grandpa" ];
            programs.hyprland.enable = true;
          }
        ] ctxSystemKhion
      );
    }
    {
      name = "value escape hatch routes users.* as ordinary config";
      pass =
        results.valueEscapeHatch == {
          users.users.alice = {
            isNormalUser = true;
          };
        };
    }
    {
      name = "a claim narrows around a value block (hit)";
      pass =
        results.valueEscapeHatchHit == {
          users.users.alice = {
            isNormalUser = true;
          };
        };
    }
    {
      name = "a claim narrows around a value block (miss drops)";
      pass = results.valueEscapeHatchMiss == { };
    }
    {
      name = "value block content is never re-scanned for claim keys";
      pass =
        results.valueNoSwallow == {
          hosts = "not-a-claim-this-is-config";
          when = "also-just-a-string";
        };
    }
    {
      name = "value + children matches the inline-config + children shape";
      pass = results.nestedViaValue == results.nested;
    }
    {
      name = "value mixed with inline config throws at author time";
      pass = throws (
        run ctx [
          {
            value = {
              users.users.alice = {
                isNormalUser = true;
              };
            };
            pkg = "x";
          }
        ]
      );
    }
    {
      name = "strict rejects an unknown host name";
      pass = throws (resolveStrict [ { pkg = "x"; } ] ctxUnknownHost);
    }
    {
      name = "strict rejects an unknown user name";
      pass = throws (resolveStrict [ { pkg = "x"; } ] ctxUnknownUser);
    }
    {
      name = "strict rejects a known but impossible host x user pair";
      pass = throws (resolveStrict [ { pkg = "x"; } ] ctxImpossiblePair);
    }
    {
      name = "strict rescues an unknown-membership user instead of rejecting it";
      pass =
        resolveStrict [ { pkg = "x"; } ] ctxRescuedUnknownMembership == {
          pkg = "x";
        };
    }
    {
      name = "strict permissive path is byte-identical to the non-strict resolve";
      pass =
        resolveStrict [
          {
            hosts = [ "khion" ];
            pkg = "khion-only";
          }
        ] ctx == results.hostHit;
    }
    {
      name = "system-scope strict validates the host only and still resolves";
      pass =
        resolveSystemStrict [
          {
            hosts = [
              "khion"
              "lumi"
            ];
            programs.hyprland.enable = true;
          }
        ] ctxSystemKhion == results.systemHostHit;
    }
    {
      name = "system-scope strict rejects an unknown host";
      pass = throws (
        resolveSystemStrict [
          {
            hosts = [
              "khion"
              "lumi"
            ];
            programs.hyprland.enable = true;
          }
        ] ctxSystemUnknownHost
      );
    }
    {
      name = "trace names host as the rejecting axis";
      pass =
        let
          leaf = builtins.head hostMissTrace.trace;
        in
        hostMissTrace.value == results.hostMiss
        && leaf.rejectedBy == [ "host" ]
        && leaf.axisResults.host.decision == "rejected";
    }
    {
      name = "trace names predicate rejection without inventing members";
      pass =
        let
          leaf = builtins.head whenMissTrace.trace;
        in
        whenMissTrace.value == results.whenMiss
        && leaf.rejectedBy == [ "when" ]
        && leaf.axisResults.when.decision == "rejected"
        && !(leaf.axisResults.when.details ? materializedMembers);
    }
    {
      name = "trace reuses diagnostic identity and reports pre-merge contribution";
      pass =
        let
          leaf = builtins.head labeledTrace.trace;
        in
        labeledTrace.value == results.labeledUnit
        && leaf.identity == "unit 'khion-only-unit'"
        && leaf.preMergeContribution.stage == "pre-merge"
        && leaf.preMergeContribution.offeredPaths == [ "pkg" ];
    }
    {
      name = "plain and trace surface entries both preserve impossible claims";
      pass =
        let
          units = [
            {
              hosts = [ "khion" ];
              children = [
                {
                  users = [ "grandpa" ];
                  pkg = "x";
                }
              ];
            }
          ];
        in
        throws (resolve units ctx) && throws (resolveTrace units ctx);
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
