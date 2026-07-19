# _lib/ownerships/descriptor-tests.nix
#
# A throwaway axis proving that one descriptor carries author syntax, scope,
# registry construction, and standalone roster projection end to end. Production
# defaults remain host, user, and when; this descriptor exists only in this test.
{ lib }:
let
  axes = import ./axes.nix { inherit lib; };
  engine = import ./engine.nix { inherit lib; };

  roleDescriptor = axes.mkSetDescriptor {
    name = "role";
    includeKey = "roles";
    excludeKey = "exceptRoles";
    includeOrder = 60;
    excludeOrder = 70;
    allowedScopes = [ "user" ];
    roster = {
      membersField = "roles";
      define = name: {
        kind = "role";
        inherit name;
      };
      project =
        { declarations, ... }:
        {
          roles = lib.unique (
            map (declaration: declaration.name) (
              builtins.filter (declaration: declaration.kind == "role") declarations
            )
          );
        };
    };
  };

  descriptors = axes.descriptors ++ [ roleDescriptor ];
  hostRoleRelation = {
    name = "host-role-membership";
    leftAxis = "host";
    rightAxis = "role";
    unknownFor = _roster: {
      left = [ ];
      right = [ ];
    };
    compatibleFor =
      roster: host: role:
      builtins.elem role (roster.roleMembership.${host} or [ ]);
    reason =
      hosts: roles:
      "no role in { ${builtins.concatStringsSep ", " roles} } belongs to any host in { ${builtins.concatStringsSep ", " hosts} }";
  };
  relations = axes.relations ++ [ hostRoleRelation ];
  surface = import ./surface.nix { inherit lib descriptors relations; };
  resolveLib = import ./resolve.nix { inherit lib descriptors relations; };

  inherit (surface)
    define
    toRoster
    mkResolve
    mkResolveSystem
    translate
    ;

  roster = toRoster [
    (define.host "khion")
    (define.user "feltfomo" { hosts = [ "khion" ]; })
    (define.role "desktop")
    (define.role "laptop")
  ];

  relationRoster = roster // {
    roleMembership."standalone/khion" = [ "desktop" ];
  };
  resolve = mkResolve relationRoster;
  resolveSystem = mkResolveSystem relationRoster;
  ctx = {
    host.name = "khion";
    user.name = "feltfomo";
    role.name = "desktop";
  };
  ctxWithoutRole = removeAttrs ctx [ "role" ];

  throws = value: !(builtins.tryEval (builtins.deepSeq value value)).success;

  missingRoleUnit = {
    roles = [ "desktop" ];
    enabled = true;
  };
  translatedMissingRole = translate missingRoleUnit;
  inherit ((resolveLib.engineArgsFor roster)) registry;
  missingRoleLeaf = builtins.head (engine.compose registry translatedMissingRole);
  missingRoleClaim = missingRoleLeaf.claim.role;
  missingRoleReason = "axis 'role' is narrowed on by claim ${
    lib.generators.toPretty { multiline = false; } missingRoleClaim
  } but the build ctx provides no entity for key 'role' -- only untagged (global) claims resolve without a build context";
  renderedMissingRole = engine.renderDiags [
    {
      kind = "missing-ctx";
      unit = missingRoleLeaf.value;
      label = null;
      source = null;
      axis = "role";
      claims = missingRoleLeaf.claim;
      reason = missingRoleReason;
    }
  ];

  userDescriptor = builtins.head (
    builtins.filter (descriptor: descriptor.name == "user") axes.descriptors
  );

  cases = [
    {
      name = "relation stages follow satisfiability in registry order";
      pass =
        map (stage: stage.name or null) (resolveLib.engineArgsFor relationRoster).stages == [
          null
          null
          "host-user-membership"
          "host-role-membership"
        ];
    }
    {
      name = "production descriptors remain host, user, and when";
      pass =
        map (descriptor: descriptor.name) axes.descriptors == [
          "host"
          "user"
          "when"
        ];
    }
    {
      name = "one role descriptor adds include and exclude author keys";
      pass =
        surface.claimKeys == [
          "hosts"
          "users"
          "exceptHosts"
          "exceptUsers"
          "when"
          "roles"
          "exceptRoles"
        ];
    }
    {
      name = "test-only host/role relation accepts a known compatible pair";
      pass =
        resolve [
          {
            hosts = [ "khion" ];
            roles = [ "desktop" ];
            enabled = true;
          }
        ] ctx == {
          enabled = true;
        };
    }
    {
      name = "test-only host/role relation rejects a known incompatible pair";
      pass = throws (
        resolve [
          {
            hosts = [ "khion" ];
            roles = [ "laptop" ];
            enabled = true;
          }
        ] ctx
      );
    }
    {
      name = "test-only host/role relation skips a global host side";
      pass = resolve [ missingRoleUnit ] ctx == { enabled = true; };
    }
    {
      name = "role include selects its matching standalone context";
      pass = resolve [ missingRoleUnit ] ctx == { enabled = true; };
    }
    {
      name = "role include drops a non-matching standalone context";
      pass = resolve [ missingRoleUnit ] (ctx // { role.name = "laptop"; }) == { };
    }
    {
      name = "role exclude keeps a context outside the excluded set";
      pass =
        resolve [
          {
            exceptRoles = [ "laptop" ];
            enabled = true;
          }
        ] ctx == {
          enabled = true;
        };
    }
    {
      name = "role exclude drops a context inside the excluded set";
      pass =
        resolve [
          {
            exceptRoles = [ "desktop" ];
            enabled = true;
          }
        ] ctx == { };
    }
    {
      name = "role projection extends the standalone roster through define.role";
      pass =
        roster.roles == [
          "desktop"
          "laptop"
        ]
        &&
          builtins.attrNames roster == [
            "aliases"
            "dimensions"
            "display"
            "hosts"
            "membership"
            "roles"
            "users"
            "usersWithUnknownMembership"
          ];
    }
    {
      name = "missing role context throws through the structured engine diagnostic path";
      pass =
        throws (resolve [ missingRoleUnit ] ctxWithoutRole)
        &&
          renderedMissingRole
          == "ownerships: 1 ownership error(s):\n  - unlabeled unit { enabled }: ${missingRoleReason} (axis 'role', claim ${
            lib.generators.toPretty { multiline = false; } missingRoleLeaf.claim
          })";
    }
    {
      name = "system scope rejects a nested role claim through the generic recursive guard";
      pass = throws (
        resolveSystem [
          {
            children = [
              {
                roles = [ "desktop" ];
                enabled = true;
              }
            ];
          }
        ] { host.name = "khion"; }
      );
    }
    {
      name = "role system-scope message is pinned";
      pass =
        roleDescriptor.scopeError "system" "roles" [ "desktop" ]
        == "ownerships: a system-scope unit sets 'roles' = [ \"desktop\" ] -- this ownership axis is unavailable in system scope";
    }
    {
      name = "user system-scope message remains byte-identical";
      pass =
        userDescriptor.scopeError "system" "users" [ "feltfomo" ]
        == "ownerships: a system-scope (host-only) unit sets 'users' = [ \"feltfomo\" ] -- a host-only slice binds no user, so it cannot narrow on users. drop the user claim or resolve this unit at user scope.";
    }
  ];

  failing = builtins.filter (case: !case.pass) cases;
  ok =
    if failing == [ ] then
      true
    else
      throw "ownerships descriptor tests FAILED: ${
        lib.concatMapStringsSep ", " (case: case.name) failing
      }";
in
{
  inherit cases ok;
}
