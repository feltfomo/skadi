# _lib/ownerships/import-units.nix
#
# deterministic standalone unit discovery. files remain ordinary ownership
# units; this module only finds, imports, normalizes, and groups them.
{ lib }:
let
  krisis = import ../krisis { inherit lib; };
  axiom = import ../axiom { inherit lib; };
  inherit (axiom) validation canonical;

  importProblem = krisis.mkDiagnosticFactory {
    severity = "error";
    codePrefix = "ownerships/import";
  };

  reporter = krisis.mkReporter { formatDiagnostic = krisis.renderPlain; };

  finish = validation.finish reporter.fail;

  failImport = reporter.failOne;

  joinRelative =
    prefix: name:
    if prefix == "" then
      name
    else
      canonical.path [
        prefix
        name
      ];
  childPath = directory: name: directory + "/${name}";
  shown = path: "'${path}'";

  discover =
    relative: directory:
    let
      entries = builtins.readDir directory;
    in
    builtins.concatMap (
      name:
      let
        kind = entries.${name};
        path = childPath directory name;
        nextRelative = joinRelative relative name;
      in
      if kind == "directory" then
        discover nextRelative path
      else if kind == "regular" then
        lib.optional (lib.hasSuffix ".nix" name) {
          inherit path;
          relative = nextRelative;
        }
      else
        failImport (importProblem {
          code = "entry-kind";
          message = "cannot import ${shown nextRelative}: filesystem entry type ${shown kind} is not a regular file or directory";
        })
    ) (builtins.attrNames entries);

  orderedFiles = directory: builtins.sort (a: b: a.relative < b.relative) (discover "" directory);

  argsDiagnostics =
    subject: args:
    validation.optional (!builtins.isAttrs args) (importProblem {
      code = "args-shape";
      message = "${subject} args must be an attribute set; got ${builtins.typeOf args}";
    });

  # a returned result rather than a throw, so one bad unit file no longer hides
  # every other bad unit file in the same tree
  normalizeFile =
    args: file:
    krisis.withErrorContext "while importing ownership units from ${shown file.relative}" (
      let
        imported = import file.path;
        result = if builtins.isFunction imported then imported args else imported;
        units = if builtins.isList result then result else [ result ];
        invalid = builtins.filter (unit: !builtins.isAttrs unit) units;
      in
      validation.fromDiagnostics (validation.optional (invalid != [ ]) (importProblem {
        code = "unit-shape";
        message = "imported unit file ${shown file.relative} must return an attribute set or a list of attribute sets; found ${builtins.typeOf (builtins.head invalid)}";
      })) units
    );

  importUnits =
    {
      dir,
      args ? { },
    }:
    let
      badArgs = argsDiagnostics "importUnits" args;
    in
    # the args shape gates the imports themselves, so it stays a separate,
    # earlier failure than the per-file accumulation
    if badArgs != [ ] then
      reporter.fail badArgs
    else
      finish (
        validation.map builtins.concatLists (validation.traverse (normalizeFile args) (orderedFiles dir))
      );

  collectionNames = [
    "home"
    "system"
  ];

  importUnitSets =
    {
      dir,
      args ? { },
    }:
    let
      entries = builtins.readDir dir;
      names = builtins.attrNames entries;
      wrongCollectionKinds = builtins.filter (
        name: builtins.elem name collectionNames && entries.${name} != "directory"
      ) names;
      looseUnits = builtins.filter (
        name: entries.${name} == "regular" && lib.hasSuffix ".nix" name
      ) names;
      unknownDirectories = builtins.filter (
        name: entries.${name} == "directory" && !(builtins.elem name collectionNames)
      ) names;
      unsafeEntries = builtins.filter (
        name:
        !(builtins.elem entries.${name} [
          "directory"
          "regular"
        ])
      ) names;
      hasHome = entries ? home && entries.home == "directory";
      hasSystem = entries ? system && entries.system == "directory";
      load =
        name:
        importUnits {
          dir = childPath dir name;
          inherit args;
        };

      # the five tree checks are independent of each other, so an author sees
      # every misplaced entry at once instead of one per rebuild
      diagnostics = validation.collect [
        (argsDiagnostics "importUnitSets" args)
        (map (
          name:
          importProblem {
            code = "collection-kind";
            message = "unit collection ${shown name} must be a directory; found ${shown entries.${name}}";
          }
        ) wrongCollectionKinds)
        (map (
          name:
          importProblem {
            code = "loose-unit";
            message = "cannot classify unit file ${shown name} in a mixed unit tree; move it under the 'system' or 'home' directory";
          }
        ) looseUnits)
        (map (
          name:
          importProblem {
            code = "unknown-collection";
            message = "unknown unit collection ${shown name}; mixed unit trees support only 'system' and 'home' directories";
          }
        ) unknownDirectories)
        (map (
          name:
          importProblem {
            code = "entry-kind";
            message = "cannot inspect unit-tree entry ${shown name}: filesystem entry type ${shown entries.${name}} is unsupported";
          }
        ) unsafeEntries)
        (validation.optional (!hasHome && !hasSystem) (importProblem {
          code = "tree-empty";
          message = "mixed unit tree must contain a 'system' or 'home' directory";
        }))
      ];
    in
    finish (
      validation.fromDiagnostics diagnostics {
        home = if hasHome then load "home" else [ ];
        system = if hasSystem then load "system" else [ ];
      }
    );
in
{
  inherit
    importUnits
    importUnitSets
    ;
}
