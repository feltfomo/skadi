# _lib/ownerships/tests/import-units.nix
{ lib }:
let
  ownerships = import ../default.nix { inherit lib; };

  throws = value: !(builtins.tryEval (builtins.deepSeq value value)).success;

  flat = ownerships.importUnits {
    dir = ./fixtures/import-units/flat;
    args = {
      marker = "passed-through";
      poison = throw "forced imported unit payload";
    };
  };

  unitSets = ownerships.importUnitSets {
    dir = ./fixtures/import-units/sets;
    args.marker = "set-marker";
  };

  roster = ownerships.toRoster [
    (ownerships.define.host "khion" { system = "x86_64-linux"; })
    (ownerships.define.user "feltfomo" { hosts = [ "khion" ]; })
  ];

  host = {
    name = "khion";
    system = "x86_64-linux";
  };
  user.name = "feltfomo";

  resolvedSystem = ownerships.mkResolveSystem roster unitSets.system { inherit host; };
  resolvedHome = ownerships.mkResolve roster unitSets.home { inherit host user; };

  cases = [
    {
      name = "importUnits recursively discovers files in deterministic relative-path order";
      pass =
        map (unit: unit.label) flat == [
          "alpha"
          "beta"
          "gamma"
        ];
    }
    {
      name = "importUnits normalizes one unit and a list into one flat collection";
      pass = builtins.length flat == 3;
    }
    {
      name = "importUnits passes caller arguments to function files";
      pass = (builtins.head flat).imported.marker == "passed-through";
    }
    {
      name = "importUnits validates only the unit shell and keeps payload fields lazy";
      pass =
        (builtins.tryEval (builtins.deepSeq (map (unit: unit.label) flat) true)).success
        && throws (builtins.head flat).imported.lazy;
    }
    {
      name = "importUnitSets discovers system and home collections in one call";
      pass =
        map (unit: unit.label) unitSets.system == [ "system fixture" ]
        && map (unit: unit.label) unitSets.home == [ "home fixture" ];
    }
    {
      name = "imported system units resolve through the public system door";
      pass =
        resolvedSystem == {
          services.ownershipsImporter = {
            enable = true;
            marker = "set-marker";
          };
        };
    }
    {
      name = "imported home units resolve through the public user door";
      pass =
        resolvedHome == {
          programs.ownershipsImporter.enable = true;
          home.sessionVariables.OWNERSHIPS_IMPORTER = "set-marker";
        };
    }
    {
      name = "mixed trees reject loose root nix files instead of guessing their scope";
      pass = throws (
        ownerships.importUnitSets {
          dir = ./fixtures/import-units/ambiguous;
        }
      );
    }
    {
      name = "mixed trees reject unknown top-level collections";
      pass = throws (
        ownerships.importUnitSets {
          dir = ./fixtures/import-units;
        }
      );
    }
    {
      name = "invalid imported values fail closed";
      pass = throws (
        ownerships.importUnits {
          dir = ./fixtures/import-units/invalid;
        }
      );
    }
    {
      name = "import helpers reject non-attribute argument bundles";
      pass =
        throws (
          ownerships.importUnits {
            dir = ./fixtures/import-units/flat;
            args = [ ];
          }
        )
        && throws (
          ownerships.importUnitSets {
            dir = ./fixtures/import-units/sets;
            args = [ ];
          }
        );
    }
  ];

  failing = builtins.filter (case: !case.pass) cases;
  ok =
    if failing == [ ] then
      true
    else
      throw "ownerships import-unit tests FAILED: ${
        lib.concatMapStringsSep ", " (case: case.name) failing
      }";
in
{
  inherit cases ok;
}
