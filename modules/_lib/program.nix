{
  lib,
  resolve,
  resolveSystem,
  resolvePrepared,
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
  themeCompiler = import ./program/theme {
    inherit
      lib
      contract
      claimKeys
      claimsOf
      withoutClaims
      unknownFields
      validRelativePath
      validBaseName
      validSubdir
      duplicateValues
      problem
      checked
      ;
  };
  inherit (themeCompiler)
    themeBackends
    themeSharedFields
    themeEntryErrors
    themeFields
    themeFiles
    themeTemplateErrors
    themeUnits
    ;
  elaborateTheme = themeCompiler.elaborate;
  normalizeThemeEntry = themeCompiler.normalizeEntry;

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
        theme = if themeIsAttrs && spec ? theme then spec.theme else { };
        unknownTheme = if themeIsAttrs && spec ? theme then unknownFields themeFields theme else [ ];
        hasTemplates = theme ? templates;
        rawTemplates =
          if !themeIsAttrs || !(spec ? theme) then
            [ ]
          else if hasTemplates && builtins.isList theme.templates then
            theme.templates
          else if hasTemplates then
            [ ]
          else
            [ (removeAttrs theme [ "id" ]) ];
        mixedThemeFields = builtins.filter (
          name: builtins.elem name (themeSharedFields ++ [ "renderers" ])
        ) (builtins.attrNames theme);
        themeErrors =
          lib.optional (!themeIsAttrs) (problem "program/theme-shape" "theme must be an attribute set")
          ++ lib.optional (unknownTheme != [ ]) (
            problem "program/theme-fields" "theme has unknown fields: ${lib.concatStringsSep ", " unknownTheme}"
          )
          ++ lib.optionals (themeIsAttrs && spec ? theme) (
            lib.optional (!(theme ? id) || !validBaseName theme.id) (
              problem "program/theme-id" "theme.id must be a normalized non-empty name"
            )
            ++ lib.optional (hasTemplates && !builtins.isList theme.templates) (
              problem "program/theme-templates-shape" "theme.templates must be a list"
            )
            ++ lib.optional (hasTemplates && mixedThemeFields != [ ]) (
              problem "program/theme-mixed-syntax" "theme cannot mix templates with single-template fields: ${lib.concatStringsSep ", " mixedThemeFields}"
            )
            ++ builtins.concatMap (
              indexed: themeTemplateErrors "theme.templates[${toString indexed.index}]" indexed.template
            ) (lib.imap0 (index: template: { inherit index template; }) rawTemplates)
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
          ++ themeErrors;
        elaborated =
          if spec ? theme && themeIsAttrs then spec // { theme = elaborateTheme theme; } else spec;
      in
      checked errors elaborated;

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

  # the read-only directory walk (readDir recursion, membership inventory) plus
  # the shape/source checks that gate it. all of it is ctx-independent, so the
  # aspect closure computes it once per directory and the per-user slices thread
  # the result through instead of re-walking the source for every user.
  prewalkDirectory =
    wrapped:
    let
      entry = if builtins.isAttrs wrapped.entry then wrapped.entry else { };
      shapeErrors = directoryShapeErrors wrapped;
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
          walkDirectory entry.src (entry.exclude or [ ])
        else
          {
            diagnostics = [ ];
            files = [ ];
            members = [ ];
          };
    in
    {
      inherit shapeErrors sourceErrors walked;
    };

  expandDirectory =
    wrapped: rules: themeEntries: pw:
    let
      inherit (pw) shapeErrors sourceErrors walked;
      entry = if builtins.isAttrs wrapped.entry then wrapped.entry else { };
      selectedRules = builtins.filter (rule: rule.index == wrapped.index) rules;
      selectedRuleErrors = builtins.concatMap directoryRuleErrors selectedRules;
      exclude = if entry ? exclude && builtins.isList entry.exclude then entry.exclude else [ ];
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
    directories: rules: themeEntries: prewalked:
    let
      emptyPrewalk = {
        shapeErrors = [ ];
        sourceErrors = [ ];
        walked = {
          diagnostics = [ ];
          files = [ ];
          members = [ ];
        };
      };
      expanded = map (
        directory:
        expandDirectory directory rules themeEntries (
          prewalked.${builtins.toString directory.index} or emptyPrewalk
        )
      ) directories;
    in
    {
      errors = builtins.concatMap (result: result.errors) expanded;
      files = builtins.concatMap (result: result.files) expanded;
    };

  validateSelected =
    files: directories: directoryFileRules: themeEntries: prewalked:
    let
      themeErrors = themeEntryErrors themeEntries;
      normalizedThemeEntries = if themeErrors == [ ] then map normalizeThemeEntry themeEntries else [ ];
      expanded = expandDirectories directories directoryFileRules normalizedThemeEntries prewalked;
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
  # the prepared resolves translate and compose the unit set once per aspect,
  # then only re-run ctx demand/select/survivors/merge per (host, user) slice.
  homeResolve = resolvePrepared homeUnits;
  furnishUnits = [ (furnishUnit spec) ];
  furnishResolve = resolvePrepared furnishUnits;
  # one read-only directory walk per declared directory, shared by every user
  # slice; shape/source errors stay once-per-aspect too.
  prewalkByIndex = builtins.listToAttrs (
    lib.imap0 (
      index: entry:
      {
        name = builtins.toString index;
        value = prewalkDirectory { inherit index entry; };
      }
    ) (spec.directories or [ ])
  );
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
      resolved = homeResolve { inherit host user; };
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
        resolved = furnishResolve { inherit host user; };
        selected = validateSelected (resolved.files or [ ]) (resolved.directoryEntries or [ ]
        ) (resolved.directoryFileRules or [ ]) (resolved.themeEntries or [ ]) prewalkByIndex;
        hostFiles = selected.files ++ selected.directoryFiles ++ themeFiles selected.themeEntries pkgs;
        principals = filePrincipals {
          inherit system user;
          host = hostName;
        };
        # theme.dms entries don't become files here: matugen only reads one
        # config.toml, so every aspect's entries are tagged with the context
        # this instantiation already has, then merged and written once by
        # program/theme/dms-runtime.nix.
        dmsThemeEntries = builtins.filter (entry: entry.renderer == "dms") selected.themeEntries;
        taggedDmsEntries = builtins.concatMap (
          principal:
          map (
            entry:
            entry
            // {
              inherit principal;
              filesystemNamespace = "${system}/${hostName}";
            }
          ) dmsThemeEntries
        ) principals;
      in
      {
        imports = [
          ./furnish/runtime.nix
          ./program/theme/dms-runtime.nix
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
              inherit principals;
              files = hostFiles;
            };
            lexicon.theme.dms.entries = taggedDmsEntries;
          }
        ]
        ++ lib.optional (spec ? nixos) rawSlice;
      };
}
