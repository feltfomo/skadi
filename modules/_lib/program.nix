{
  lib,
  resolve,
  resolveSystem,
  filePrincipals,
  hostUserNames,
}:
let
  furnish = import ./furnish { inherit lib resolve resolveSystem; };
  krisis = import ./krisis { inherit lib; };
  ownerships = import ./ownerships { inherit lib; };
  inherit (furnish) contract;
  inherit (ownerships) claimKeys;
  furnishFiles = furnish.files;

  claimKeysAttrs = lib.genAttrs claimKeys (_: null);
  lifecycleKeys = [
    "representation"
    "onConflict"
    "provenance"
  ];
  lifecycleKeysAttrs = lib.genAttrs lifecycleKeys (_: null);
  conflictPolicies = builtins.attrValues contract.conflictPolicies;

  specFields = claimKeys ++ [
    "pkg"
    "nixos"
    "imports"
    "files"
    "directories"
    "theme"
  ];
  fileFields = claimKeys ++ [
    "dest"
    "src"
    "label"
    "representation"
    "onConflict"
    "provenance"
  ];
  directoryFields = claimKeys ++ [
    "src"
    "dest"
    "exclude"
    "files"
    "representation"
    "onConflict"
    "provenance"
  ];
  directoryRuleFields = claimKeys ++ [
    "names"
    "representation"
    "onConflict"
    "provenance"
  ];
  themeEntryFields = claimKeys ++ [
    "source"
    "output"
    "subdir"
    "placedAs"
    "subId"
    "reload"
    "native"
  ];
  themeBackends = [
    "noctalia"
    "dms"
  ];

  claimsOf =
    value: if builtins.isAttrs value then builtins.intersectAttrs claimKeysAttrs value else { };
  withoutClaims = value: if builtins.isAttrs value then removeAttrs value claimKeys else value;

  validRelativePath =
    value:
    builtins.isString value
    && value != ""
    && !lib.hasPrefix "/" value
    && builtins.all (part: part != "" && part != "." && part != "..") (lib.splitString "/" value);

  validBaseName = value: validRelativePath value && builtins.length (lib.splitString "/" value) == 1;

  validSubdir =
    value: builtins.isString value && (value == "" || validRelativePath (lib.removeSuffix "/" value));

  unknownFields =
    allowed: value:
    if !builtins.isAttrs value then
      [ ]
    else
      builtins.filter (name: !(builtins.elem name allowed)) (builtins.attrNames value);

  duplicateValues =
    values:
    builtins.attrNames (
      lib.filterAttrs (_: group: builtins.length group > 1) (builtins.groupBy (value: value) values)
    );

  joinSource =
    root: relative:
    if relative == "" then
      root
    else if builtins.isPath root then
      root + "/${relative}"
    else
      "${lib.removeSuffix "/" root}/${relative}";

  problem =
    code: message:
    krisis.mkDiagnostic {
      severity = "error";
      inherit code message;
    };

  checked =
    diagnostics: value:
    if diagnostics == [ ] then
      value
    else
      krisis.throwDiagnostics {
        inherit diagnostics;
        formatHeader = count: "program: ${toString count} declaration error(s)";
        formatDiagnostic = diagnostic: "  - [${diagnostic.code}] ${diagnostic.message}";
      };

  validateSpec =
    spec:
    if !builtins.isAttrs spec then
      checked [ (problem "program/spec-shape" "declaration must be an attribute set") ] spec
    else
      let
        unknownSpec = unknownFields specFields spec;
        themeIsAttrs = !(spec ? theme) || builtins.isAttrs spec.theme;
        unknownTheme = if themeIsAttrs && spec ? theme then unknownFields themeBackends spec.theme else [ ];
        themeBlockErrors =
          backend:
          let
            block = if themeIsAttrs then spec.theme.${backend} or null else null;
            blockIsAttrs = block == null || builtins.isAttrs block;
            blockAllowed =
              if blockIsAttrs && block != null && block ? templates then
                [
                  "id"
                  "templates"
                ]
              else
                [ "id" ] ++ themeEntryFields;
            unknownBlock = if blockIsAttrs && block != null then unknownFields blockAllowed block else [ ];
          in
          lib.optional (!blockIsAttrs) (
            problem "program/${backend}-shape" "theme.${backend} must be an attribute set"
          )
          ++ lib.optionals (blockIsAttrs && block != null) (
            lib.optional (!(block ? id) || !validBaseName block.id) (
              problem "program/${backend}-id" "theme.${backend}.id must be a normalized non-empty name"
            )
            ++ lib.optional (block ? templates && !builtins.isList block.templates) (
              problem "program/${backend}-templates-shape" "theme.${backend}.templates must be a list"
            )
            ++
              lib.optional
                (
                  block ? templates
                  && builtins.any (name: builtins.elem name themeEntryFields) (builtins.attrNames block)
                )
                (
                  problem "program/${backend}-mixed-syntax" "theme.${backend} cannot mix templates with single-entry fields"
                )
            ++ lib.optional (unknownBlock != [ ]) (
              problem "program/${backend}-block-fields" "theme.${backend} has unknown fields: ${lib.concatStringsSep ", " unknownBlock}"
            )
          );
        errors =
          lib.optional (unknownSpec != [ ]) (
            problem "program/spec-fields" "declaration has unknown fields: ${lib.concatStringsSep ", " unknownSpec}"
          )
          ++ lib.optional (spec ? pkg && !builtins.isFunction spec.pkg) (
            problem "program/pkg-shape" "pkg must be a function"
          )
          ++ lib.optional (spec ? nixos && !builtins.isFunction spec.nixos) (
            problem "program/nixos-shape" "nixos must be a function"
          )
          ++ lib.optional (spec ? imports && !builtins.isList spec.imports) (
            problem "program/imports-shape" "imports must be a list"
          )
          ++ lib.optional (spec ? files && !builtins.isList spec.files) (
            problem "program/files-shape" "files must be a list"
          )
          ++ lib.optional (spec ? directories && !builtins.isList spec.directories) (
            problem "program/directories-shape" "directories must be a list"
          )
          ++ lib.optional (!themeIsAttrs) (problem "program/theme-shape" "theme must be an attribute set")
          ++ lib.optional (unknownTheme != [ ]) (
            problem "program/theme-fields" "theme has unknown fields: ${lib.concatStringsSep ", " unknownTheme}"
          )
          ++ builtins.concatMap themeBlockErrors themeBackends;
      in
      checked errors spec;

  entryUnit =
    fieldName: entry:
    claimsOf entry
    // {
      ${fieldName} = [ (withoutClaims entry) ];
    };

  safeRuleNames =
    rule:
    if builtins.isAttrs rule && rule ? names && builtins.isList rule.names then
      builtins.filter builtins.isString rule.names
    else
      [ ];

  directoryUnit =
    index: directory:
    let
      body = withoutClaims directory;
      rules =
        if builtins.isAttrs directory && directory ? files && builtins.isList directory.files then
          directory.files
        else
          [ ];
      parentClaims = claimsOf directory;
    in
    parentClaims
    // {
      children = [
        {
          directoryEntries = [
            {
              inherit index;
              entry = body;
              reservedNames = builtins.concatMap safeRuleNames rules;
            }
          ];
        }
      ]
      ++ map (
        rule:
        claimsOf rule
        // {
          directoryFileRules = [
            {
              inherit index;
              entry = withoutClaims rule;
            }
          ];
        }
      ) rules;
    };

  # theme entries stay descriptive until ownership has selected them.
  themeUnitsFor =
    spec: renderer:
    let
      block = spec.theme.${renderer} or null;
    in
    if block == null then
      [ ]
    else
      let
        inherit (block) id;
        rawEntries = block.templates or [ (removeAttrs block [ "id" ]) ];
      in
      map (
        raw:
        claimsOf raw
        // {
          themeEntries = [
            {
              inherit renderer;
              blockId = id;
              entry = withoutClaims raw;
            }
          ];
        }
      ) rawEntries;

  themeUnits = spec: builtins.concatMap (themeUnitsFor spec) themeBackends;

  furnishUnit =
    spec:
    claimsOf spec
    // {
      children =
        map (entryUnit "files") (spec.files or [ ])
        ++ lib.imap0 directoryUnit (spec.directories or [ ])
        ++ themeUnits spec;
    };

  specUnit =
    spec:
    let
      pkg = spec.pkg or null;
      imports = spec.imports or [ ];
    in
    claimsOf spec
    // {
      children =
        lib.optional (pkg != null) { inherit pkg; } ++ lib.optional (imports != [ ]) { inherit imports; };
    };

  fileErrors =
    files:
    builtins.concatMap (
      indexed:
      let
        inherit (indexed) index entry;
        subject = "files[${toString index}]";
        unknown = unknownFields fileFields entry;
      in
      if !builtins.isAttrs entry then
        [ (problem "program/file-entry-shape" "${subject} must be an attribute set") ]
      else
        lib.optional (unknown != [ ]) (
          problem "program/file-fields" "${subject} has unknown fields: ${lib.concatStringsSep ", " unknown}"
        )
        ++ lib.optional (!(entry ? dest) || !builtins.isString entry.dest || entry.dest == "") (
          problem "program/file-destination" "${subject}.dest must be a non-empty string"
        )
        ++ lib.optional (!(entry ? src)) (problem "program/file-source" "${subject}.src is required")
        ++ lib.optional (entry ? label && !builtins.isString entry.label) (
          problem "program/file-label" "${subject}.label must be a string"
        )
        ++ lib.optional (entry ? provenance && !builtins.isString entry.provenance) (
          problem "program/file-provenance" "${subject}.provenance must be a string"
        )
        ++ lib.optional (
          entry ? representation && (!builtins.isString entry.representation || entry.representation == "")
        ) (problem "program/file-representation" "${subject}.representation must be a non-empty string")
        ++
          lib.optional
            (
              entry ? onConflict
              && (!builtins.isString entry.onConflict || !(builtins.elem entry.onConflict conflictPolicies))
            )
            (problem "program/file-conflict-policy" "${subject}.onConflict must be a declared conflict policy")
    ) (lib.imap0 (index: entry: { inherit index entry; }) files);

  directoryShapeErrors =
    wrapped:
    let
      subject = "directories[${toString wrapped.index}]";
      inherit (wrapped) entry;
      unknown = unknownFields directoryFields entry;
    in
    if !builtins.isAttrs entry then
      [ (problem "program/directory-entry-shape" "${subject} must be an attribute set") ]
    else
      lib.optional (unknown != [ ]) (
        problem "program/directory-fields" "${subject} has unknown fields: ${lib.concatStringsSep ", " unknown}"
      )
      ++ lib.optional (!(entry ? src)) (problem "program/directory-source" "${subject}.src is required")
      ++ lib.optional (entry ? src && !(builtins.isPath entry.src || builtins.isString entry.src)) (
        problem "program/directory-source-shape" "${subject}.src must be a path or string"
      )
      ++ lib.optional (!(entry ? dest) || !builtins.isString entry.dest || entry.dest == "") (
        problem "program/directory-destination" "${subject}.dest must be a non-empty string"
      )
      ++ lib.optional (entry ? exclude && !builtins.isList entry.exclude) (
        problem "program/directory-exclude-shape" "${subject}.exclude must be a list"
      )
      ++ lib.optionals (entry ? exclude && builtins.isList entry.exclude) (
        lib.optional (!(builtins.all validRelativePath entry.exclude)) (
          problem "program/directory-exclude-name" "${subject}.exclude must contain normalized relative paths"
        )
      )
      ++ lib.optional (entry ? files && !builtins.isList entry.files) (
        problem "program/directory-files-shape" "${subject}.files must be a list"
      )
      ++
        lib.optional
          (entry ? representation && (!builtins.isString entry.representation || entry.representation == ""))
          (problem "program/directory-representation" "${subject}.representation must be a non-empty string")
      ++
        lib.optional
          (
            entry ? onConflict
            && (!builtins.isString entry.onConflict || !(builtins.elem entry.onConflict conflictPolicies))
          )
          (
            problem "program/directory-conflict-policy" "${subject}.onConflict must be a declared conflict policy"
          )
      ++ lib.optional (entry ? provenance && !builtins.isString entry.provenance) (
        problem "program/directory-provenance" "${subject}.provenance must be a string"
      );

  directoryRuleErrors =
    wrapped:
    let
      subject = "directories[${toString wrapped.index}].files";
      inherit (wrapped) entry;
      unknown = unknownFields directoryRuleFields entry;
    in
    if !builtins.isAttrs entry then
      [ (problem "program/directory-file-shape" "${subject} entries must be attribute sets") ]
    else
      lib.optional (unknown != [ ]) (
        problem "program/directory-file-fields" "${subject} has unknown fields: ${lib.concatStringsSep ", " unknown}"
      )
      ++ lib.optional (!(entry ? names) || !builtins.isList entry.names || entry.names == [ ]) (
        problem "program/directory-file-names" "${subject}.names must be a non-empty list"
      )
      ++ lib.optionals (entry ? names && builtins.isList entry.names) (
        lib.optional (!(builtins.all validRelativePath entry.names)) (
          problem "program/directory-file-name" "${subject}.names must contain normalized relative paths"
        )
      )
      ++
        lib.optional
          (entry ? representation && (!builtins.isString entry.representation || entry.representation == ""))
          (
            problem "program/directory-file-representation" "${subject}.representation must be a non-empty string"
          )
      ++
        lib.optional
          (
            entry ? onConflict
            && (!builtins.isString entry.onConflict || !(builtins.elem entry.onConflict conflictPolicies))
          )
          (
            problem "program/directory-file-conflict-policy" "${subject}.onConflict must be a declared conflict policy"
          )
      ++ lib.optional (entry ? provenance && !builtins.isString entry.provenance) (
        problem "program/directory-file-provenance" "${subject}.provenance must be a string"
      );

  excludedBy =
    exclusions: name:
    builtins.any (excluded: name == excluded || lib.hasPrefix "${excluded}/" name) exclusions;

  walkDirectory =
    root: exclusions:
    let
      walk =
        relative:
        let
          current = joinSource root relative;
          scanned = builtins.tryEval (builtins.readDir current);
        in
        if !scanned.success then
          {
            diagnostics = [
              (problem "program/directory-source-kind" "directory source ${toString current} is not readable as a directory")
            ];
            files = [ ];
            members = [ ];
          }
        else
          let
            resultFor =
              name:
              let
                kind = scanned.value.${name};
                child = if relative == "" then name else "${relative}/${name}";
                excluded = builtins.elem child exclusions;
                base = {
                  diagnostics = [ ];
                  files = [ ];
                  members = [ child ];
                };
              in
              if excluded then
                base
              else if kind == "directory" then
                let
                  nested = walk child;
                in
                {
                  inherit (nested) diagnostics files;
                  members = [ child ] ++ nested.members;
                }
              else if kind == "regular" then
                base // { files = [ child ]; }
              else
                base
                // {
                  diagnostics = [
                    (problem "program/directory-member-kind" "directory source member ${child} must be a regular file or directory, not ${kind}")
                  ];
                };
            results = map resultFor (builtins.attrNames scanned.value);
          in
          {
            diagnostics = builtins.concatMap (result: result.diagnostics) results;
            files = builtins.concatMap (result: result.files) results;
            members = builtins.concatMap (result: result.members) results;
          };
    in
    walk "";

  sourceRelativeTo =
    root: source:
    let
      rootString = lib.removeSuffix "/" (builtins.unsafeDiscardStringContext (toString root));
      prefix = "${rootString}/";
      sourceString = builtins.unsafeDiscardStringContext (toString source);
    in
    if lib.hasPrefix prefix sourceString then lib.removePrefix prefix sourceString else null;

  expandDirectory =
    wrapped: rules: themeEntries:
    let
      shapeErrors = directoryShapeErrors wrapped;
      entry = if builtins.isAttrs wrapped.entry then wrapped.entry else { };
      selectedRules = builtins.filter (rule: rule.index == wrapped.index) rules;
      selectedRuleErrors = builtins.concatMap directoryRuleErrors selectedRules;
      exclude = if entry ? exclude && builtins.isList entry.exclude then entry.exclude else [ ];
      sourceKind =
        if shapeErrors != [ ] then
          null
        else if !builtins.pathExists entry.src then
          "missing"
        else
          builtins.readFileType entry.src;
      sourceErrors =
        lib.optional (shapeErrors == [ ] && sourceKind == "missing") (
          problem "program/directory-source-missing" "directories[${toString wrapped.index}].src does not exist in the flake source: ${toString entry.src}. git-backed flakes omit empty and untracked directories; add a tracked file beneath the directory or remove the declaration"
        )
        ++ lib.optional (shapeErrors == [ ] && sourceKind != "missing" && sourceKind != "directory") (
          problem "program/directory-source-kind" "directories[${toString wrapped.index}].src must be a directory: ${toString entry.src} is ${sourceKind}"
        );
      walked =
        if sourceErrors == [ ] && shapeErrors == [ ] then
          walkDirectory entry.src exclude
        else
          {
            diagnostics = [ ];
            files = [ ];
            members = [ ];
          };
      inventory = walked.files;
      reserved = wrapped.reservedNames;
      uniqueReserved = lib.unique reserved;
      duplicateReserved = duplicateValues reserved;
      unknownExcluded = builtins.filter (name: !(builtins.elem name walked.members)) exclude;
      excludedOverrides = builtins.filter (excludedBy exclude) uniqueReserved;
      unknownReserved = builtins.filter (
        name: !(excludedBy exclude name) && !(builtins.elem name inventory)
      ) uniqueReserved;
      themeNames = builtins.filter (name: name != null) (
        map (theme: sourceRelativeTo entry.src theme.source) themeEntries
      );
      excludedThemes = builtins.filter (excludedBy exclude) themeNames;
      themeOverrides = builtins.filter (name: builtins.elem name themeNames) uniqueReserved;
      semanticErrors =
        lib.optional (duplicateReserved != [ ]) (
          problem "program/directory-file-duplicate" "directories[${toString wrapped.index}] repeats override names: ${lib.concatStringsSep ", " duplicateReserved}"
        )
        ++ lib.optional (unknownExcluded != [ ]) (
          problem "program/directory-exclude-unknown" "directories[${toString wrapped.index}] excludes unknown names: ${lib.concatStringsSep ", " unknownExcluded}"
        )
        ++ lib.optional (unknownReserved != [ ]) (
          problem "program/directory-file-unknown" "directories[${toString wrapped.index}] overrides unknown names: ${lib.concatStringsSep ", " unknownReserved}"
        )
        ++ lib.optional (excludedOverrides != [ ]) (
          problem "program/directory-file-excluded" "directories[${toString wrapped.index}] overrides excluded names: ${lib.concatStringsSep ", " excludedOverrides}"
        )
        ++ lib.optional (excludedThemes != [ ]) (
          problem "program/directory-theme-excluded" "directories[${toString wrapped.index}] excludes theme sources: ${lib.concatStringsSep ", " excludedThemes}"
        )
        ++ lib.optional (themeOverrides != [ ]) (
          problem "program/directory-file-themed" "directories[${toString wrapped.index}] overrides theme sources: ${lib.concatStringsSep ", " themeOverrides}"
        );
      defaults = builtins.intersectAttrs lifecycleKeysAttrs entry;
      destinationRoot = lib.removeSuffix "/" (entry.dest or "");
      fileFor =
        extra: name:
        defaults
        // builtins.intersectAttrs lifecycleKeysAttrs extra
        // {
          src = joinSource entry.src name;
          dest = "${destinationRoot}/${name}";
        };
      inheritedNames = builtins.filter (
        name: !(builtins.elem name reserved) && !(builtins.elem name themeNames)
      ) inventory;
      selectedFiles = builtins.concatMap (
        rule:
        if builtins.isAttrs rule.entry && rule.entry ? names && builtins.isList rule.entry.names then
          map (fileFor rule.entry) rule.entry.names
        else
          [ ]
      ) selectedRules;
      errors = shapeErrors ++ selectedRuleErrors ++ sourceErrors ++ walked.diagnostics ++ semanticErrors;
    in
    {
      inherit errors;
      files = if errors == [ ] then map (fileFor { }) inheritedNames ++ selectedFiles else [ ];
    };

  expandDirectories =
    directories: rules: themeEntries:
    let
      expanded = map (directory: expandDirectory directory rules themeEntries) directories;
    in
    {
      errors = builtins.concatMap (result: result.errors) expanded;
      files = builtins.concatMap (result: result.files) expanded;
    };

  themeEntryErrors =
    themeEntries:
    builtins.concatMap (
      indexed:
      let
        inherit (indexed) index wrapped;
        subject = "theme.${wrapped.renderer}.${wrapped.blockId}.templates[${toString index}]";
        inherit (wrapped) entry;
        unknown = unknownFields themeEntryFields entry;
      in
      if !builtins.isAttrs entry then
        [ (problem "program/theme-entry-shape" "${subject} must be an attribute set") ]
      else
        lib.optional (unknown != [ ]) (
          problem "program/theme-entry-fields" "${subject} has unknown fields: ${lib.concatStringsSep ", " unknown}"
        )
        ++ lib.optional (
          !(entry ? source) || !(builtins.isPath entry.source || builtins.isString entry.source)
        ) (problem "program/theme-source" "${subject}.source must be a path or string")
        ++ lib.optional (!(entry ? output) || !validRelativePath entry.output) (
          problem "program/theme-output" "${subject}.output must be a normalized relative path"
        )
        ++ lib.optional (entry ? subdir && entry.subdir != null && !validSubdir entry.subdir) (
          problem "program/theme-subdir" "${subject}.subdir must be null, empty, or a normalized relative directory"
        )
        ++ lib.optional (entry ? placedAs && !validBaseName entry.placedAs) (
          problem "program/theme-placed-name" "${subject}.placedAs must be a normalized basename"
        )
        ++ lib.optional (entry ? subId && entry.subId != null && !validBaseName entry.subId) (
          problem "program/theme-sub-id" "${subject}.subId must be null or a normalized non-empty name"
        )
        ++ lib.optional (entry ? reload && entry.reload != null && !builtins.isString entry.reload) (
          problem "program/theme-reload" "${subject}.reload must be null or a string"
        )
        ++ lib.optional (entry ? native && !builtins.isAttrs entry.native) (
          problem "program/theme-native" "${subject}.native must be an attribute set"
        )
    ) (lib.imap0 (index: wrapped: { inherit index wrapped; }) themeEntries);

  normalizeThemeEntry =
    wrapped:
    let
      inherit (wrapped) blockId renderer;
      inherit (wrapped.entry) source output;
      inherit (wrapped) entry;
      rawSubdir =
        if !(entry ? subdir) then
          blockId
        else if entry.subdir == null then
          ""
        else
          lib.removeSuffix "/" entry.subdir;
      subdir = if rawSubdir == "" then "" else "${rawSubdir}/";
      # the placed name must not retain the source path's string context.
      placedAs = entry.placedAs or (builtins.unsafeDiscardStringContext (baseNameOf source));
      subId = entry.subId or null;
    in
    {
      inherit
        source
        output
        subdir
        placedAs
        subId
        blockId
        renderer
        ;
      reload = entry.reload or null;
      native = entry.native or { };
      registrationId = if subId == null then blockId else "${blockId}-${subId}";
    };

  validateSelected =
    files: directories: directoryFileRules: themeEntries:
    let
      themeErrors = themeEntryErrors themeEntries;
      normalizedThemeEntries = if themeErrors == [ ] then map normalizeThemeEntry themeEntries else [ ];
      expanded = expandDirectories directories directoryFileRules normalizedThemeEntries;
      errors = fileErrors files ++ themeErrors ++ expanded.errors;
    in
    checked errors {
      inherit files;
      directoryFiles = expanded.files;
      themeEntries = normalizedThemeEntries;
    };

  hmConfig =
    lib: resolved: pkgs:
    let
      pkg = resolved.pkg or null;
    in
    lib.mkIf (pkg != null) {
      home.packages = [ (pkg pkgs) ];
    };

  themeGroupFiles =
    pkgs: entries:
    let
      inherit ((builtins.head entries)) blockId renderer;
      ids = map (entry: entry.registrationId) entries;
      dupIds = duplicateValues ids;
      templateRoot =
        if renderer == "noctalia" then ".config/noctalia/templates" else ".config/matugen/dms/templates";
      seedFileOf = entry: {
        dest = "${templateRoot}/${entry.subdir}${entry.placedAs}";
        src = entry.source;
        representation = contract.capabilities.writable;
        onConflict = contract.conflictPolicies.runtimeWins;
        provenance = "modules/_lib/program.nix";
      };
      registrationOf =
        entry:
        entry.native
        // {
          input_path = "~/${templateRoot}/${entry.subdir}${entry.placedAs}";
          output_path = "~/${entry.output}";
        }
        // lib.optionalAttrs (entry.reload != null) { post_hook = entry.reload; };
      registrations = builtins.listToAttrs (
        map (entry: {
          name = entry.registrationId;
          value = registrationOf entry;
        }) entries
      );
      fragmentAttrset =
        if renderer == "noctalia" then
          { theme.templates.user = registrations; }
        else
          { templates = registrations; };
      fragmentDestination =
        if renderer == "noctalia" then
          ".config/noctalia/${blockId}.toml"
        else
          ".config/matugen/dms/configs/${blockId}.toml";
    in
    if dupIds != [ ] then
      checked
        [
          (problem "program/theme-registration-duplicate" "theme.${renderer}.${blockId} has duplicate registration ids: ${lib.concatStringsSep ", " dupIds}")
        ]
        [ ]
    else
      map seedFileOf entries
      ++ [
        {
          dest = fragmentDestination;
          src = (pkgs.formats.toml { }).generate "${renderer}-${blockId}.toml" fragmentAttrset;
          provenance = "modules/_lib/program.nix";
        }
      ];

  themeFiles =
    entries: pkgs:
    builtins.concatMap (themeGroupFiles pkgs) (
      builtins.attrValues (builtins.groupBy (entry: "${entry.renderer}:${entry.blockId}") entries)
    );
in
rawSpec:
let
  spec = validateSpec rawSpec;
  ownsFiles =
    (spec.files or [ ]) != [ ]
    || (spec.directories or [ ]) != [ ]
    || builtins.any (backend: (spec.theme.${backend} or null) != null) themeBackends;
  needsHomeManager = (spec.pkg or null) != null || (spec.imports or [ ]) != [ ];
  homeUnits = [ (specUnit spec) ];
in
lib.optionalAttrs needsHomeManager {
  homeManager =
    {
      pkgs,
      lib,
      host ? null,
      user ? null,
      ...
    }:
    let
      resolved = (resolve homeUnits) { inherit host user; };
    in
    {
      imports = resolved.imports or [ ];
      config = hmConfig lib resolved pkgs;
    };
}
// lib.optionalAttrs (spec ? nixos || ownsFiles) {
  nixos =
    {
      pkgs,
      config,
      host ? null,
      user ? null,
      ...
    }:
    let
      rawSlice =
        if spec ? nixos then
          (resolveSystem (spec.nixos { inherit pkgs config; })) { inherit host; }
        else
          { };
    in
    if !ownsFiles then
      rawSlice
    else
      let
        hostName = config.networking.hostName;
        inherit (pkgs.stdenv.hostPlatform) system;
        resolved = (resolve [ (furnishUnit spec) ]) { inherit host user; };
        selected = validateSelected (resolved.files or [ ]) (resolved.directoryEntries or [ ]
        ) (resolved.directoryFileRules or [ ]) (resolved.themeEntries or [ ]);
        hostFiles = selected.files ++ selected.directoryFiles ++ themeFiles selected.themeEntries pkgs;
      in
      {
        imports = [
          ./furnish/runtime.nix
          {
            assertions = lib.optional (hostFiles != [ ]) {
              assertion = config.lexicon.furnish.declarations != [ ];
              message = "furnish: file entries on ${hostName} reached no user principal (have: ${
                lib.concatStringsSep ", " (hostUserNames {
                  inherit system;
                  host = hostName;
                })
              })";
            };
            # den reaches this slice once per selected user.
            lexicon.furnish.declarations = furnishFiles.mkDeclarations {
              filesystemNamespace = "${system}/${hostName}";
              principals = filePrincipals {
                inherit system user;
                host = hostName;
              };
              files = hostFiles;
            };
          }
        ]
        ++ lib.optional (spec ? nixos) rawSlice;
      };
}
