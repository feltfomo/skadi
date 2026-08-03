# _lib/ownerships/import-units.nix
#
# deterministic standalone unit discovery. Files remain ordinary ownership
# units; this module only finds, imports, normalizes, and groups them.
{ lib }:
let
  joinRelative = prefix: name: if prefix == "" then name else "${prefix}/${name}";
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
        throw "ownerships: cannot import ${shown nextRelative}: filesystem entry type ${shown kind} is not a regular file or directory"
    ) (builtins.attrNames entries);

  orderedFiles = directory: builtins.sort (a: b: a.relative < b.relative) (discover "" directory);

  normalizeFile =
    args: file:
    builtins.addErrorContext "while importing ownership units from ${shown file.relative}" (
      let
        imported = import file.path;
        result = if builtins.isFunction imported then imported args else imported;
        units = if builtins.isList result then result else [ result ];
        invalid = builtins.filter (unit: !builtins.isAttrs unit) units;
      in
      if invalid == [ ] then
        units
      else
        throw "ownerships: imported unit file ${shown file.relative} must return an attribute set or a list of attribute sets; found ${builtins.typeOf (builtins.head invalid)}"
    );

  importUnits =
    {
      dir,
      args ? { },
    }:
    if !builtins.isAttrs args then
      throw "ownerships: importUnits args must be an attribute set; got ${builtins.typeOf args}"
    else
      builtins.concatLists (map (normalizeFile args) (orderedFiles dir));

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
    in
    if !builtins.isAttrs args then
      throw "ownerships: importUnitSets args must be an attribute set; got ${builtins.typeOf args}"
    else if wrongCollectionKinds != [ ] then
      let
        name = builtins.head wrongCollectionKinds;
      in
      throw "ownerships: unit collection ${shown name} must be a directory; found ${shown entries.${name}}"
    else if looseUnits != [ ] then
      let
        name = builtins.head looseUnits;
      in
      throw "ownerships: cannot classify unit file ${shown name} in a mixed unit tree; move it under the 'system' or 'home' directory"
    else if unknownDirectories != [ ] then
      let
        name = builtins.head unknownDirectories;
      in
      throw "ownerships: unknown unit collection ${shown name}; mixed unit trees support only 'system' and 'home' directories"
    else if unsafeEntries != [ ] then
      let
        name = builtins.head unsafeEntries;
      in
      throw "ownerships: cannot inspect unit-tree entry ${shown name}: filesystem entry type ${shown entries.${name}} is unsupported"
    else if !hasHome && !hasSystem then
      throw "ownerships: mixed unit tree must contain a 'system' or 'home' directory"
    else
      {
        home = if hasHome then load "home" else [ ];
        system = if hasSystem then load "system" else [ ];
      };
in
{
  inherit
    importUnits
    importUnitSets
    ;
}
