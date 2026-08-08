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
  ownerships = import ./ownerships { inherit lib; };
  inherit (furnish) contract;
  inherit (ownerships) claimKeys;
  axiom = import ./axiom { inherit lib; };
  programReport = import ./program/report.nix { inherit lib; };
  inherit (programReport) problem reporter duplicateValues;
  inherit (reporter) checked;
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
      reporter
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

  joinSource =
    root: relative:
    if relative == "" then
      root
    else if builtins.isPath root then
      root + "/${relative}"
    else
      axiom.canonical.path [
        (lib.removeSuffix "/" root)
        relative
      ];

  labeled =
    subject: code: message:
    problem {
      inherit code message;
      primary.label = subject;
    };

  requiredLabeled = subject: code: message: predicate: {
    required = true;
    validate = predicate;
    onMissing = _entry: labeled subject code message;
    onInvalid = _entry: _value: labeled subject code message;
  };

  optionalLabeled = subject: code: message: predicate: {
    validate = predicate;
    onInvalid = _entry: _value: labeled subject code message;
  };

  nonEmptyString = value: builtins.isString value && value != "";
  declaredPolicy = value: builtins.isString value && builtins.elem value conflictPolicies;

  # the entry vocabularies are closed, so an unknown key is a typo and each one
  # gets named on its own instead of collapsing into a single joined message
  specSchema = axiom.schema.compile {
    onRecord =
      _value:
      problem {
        code = "spec-shape";
        message = "declaration must be an attribute set";
      };
    onUnknown =
      name: _value:
      problem {
        code = "spec-fields";
        message = "declaration has unknown field ${name}";
      };
    order = specFields;
    fields = lib.genAttrs claimKeys (_: { }) // {
      pkg = {
        validate = builtins.isFunction;
        onInvalid =
          _spec: _value:
          problem {
            code = "pkg-shape";
            message = "pkg must be a function";
          };
      };
      nixos = {
        validate = builtins.isFunction;
        onInvalid =
          _spec: _value:
          problem {
            code = "nixos-shape";
            message = "nixos must be a function";
          };
      };
      imports = {
        validate = builtins.isList;
        onInvalid =
          _spec: _value:
          problem {
            code = "imports-shape";
            message = "imports must be a list";
          };
      };
      files = {
        validate = builtins.isList;
        onInvalid =
          _spec: _value:
          problem {
            code = "files-shape";
            message = "files must be a list";
          };
      };
      directories = {
        validate = builtins.isList;
        onInvalid =
          _spec: _value:
          problem {
            code = "directories-shape";
            message = "directories must be a list";
          };
      };
      theme = {
        validate = builtins.isAttrs;
        onInvalid =
          _spec: _value:
          problem {
            code = "theme-shape";
            message = "theme must be an attribute set";
          };
      };
    };
  };

  fileSchema =
    subject:
    axiom.schema.compile {
      onRecord = _value: labeled subject "file-entry-shape" "must be an attribute set";
      onUnknown = name: _value: labeled subject "file-fields" "has unknown field ${name}";
      order = fileFields;
      fields = lib.genAttrs claimKeys (_: { }) // {
        dest = requiredLabeled subject "file-destination" "dest must be a non-empty string" nonEmptyString;
        src = {
          required = true;
          onMissing = _entry: labeled subject "file-source" "src is required";
        };
        label = optionalLabeled subject "file-label" "label must be a string" builtins.isString;
        representation =
          optionalLabeled subject "file-representation" "representation must be a non-empty string"
            nonEmptyString;
        onConflict =
          optionalLabeled subject "file-conflict-policy" "onConflict must be a declared conflict policy"
            declaredPolicy;
        provenance =
          optionalLabeled subject "file-provenance" "provenance must be a string"
            builtins.isString;
      };
    };

  directorySchema =
    subject:
    axiom.schema.compile {
      onRecord = _value: labeled subject "directory-entry-shape" "must be an attribute set";
      onUnknown = name: _value: labeled subject "directory-fields" "has unknown field ${name}";
      order = directoryFields;
      fields = lib.genAttrs claimKeys (_: { }) // {
        src = {
          required = true;
          validate = value: builtins.isPath value || builtins.isString value;
          onMissing = _entry: labeled subject "directory-source" "src is required";
          onInvalid = _entry: _value: labeled subject "directory-source-shape" "src must be a path or string";
        };
        dest =
          requiredLabeled subject "directory-destination" "dest must be a non-empty string"
            nonEmptyString;
        exclude = {
          validate = value: builtins.isList value && builtins.all validRelativePath value;
          onInvalid =
            _entry: value:
            if !builtins.isList value then
              labeled subject "directory-exclude-shape" "exclude must be a list"
            else
              labeled subject "directory-exclude-name" "exclude must contain normalized relative paths";
        };
        files = optionalLabeled subject "directory-files-shape" "files must be a list" builtins.isList;
        representation =
          optionalLabeled subject "directory-representation" "representation must be a non-empty string"
            nonEmptyString;
        onConflict =
          optionalLabeled subject "directory-conflict-policy" "onConflict must be a declared conflict policy"
            declaredPolicy;
        provenance =
          optionalLabeled subject "directory-provenance" "provenance must be a string"
            builtins.isString;
      };
    };

  directoryRuleSchema =
    subject:
    axiom.schema.compile {
      onRecord = _value: labeled subject "directory-file-shape" "entries must be attribute sets";
      onUnknown = name: _value: labeled subject "directory-file-fields" "has unknown field ${name}";
      order = directoryRuleFields;
      fields = lib.genAttrs claimKeys (_: { }) // {
        names = {
          required = true;
          validate = value: builtins.isList value && value != [ ] && builtins.all validRelativePath value;
          onMissing = _entry: labeled subject "directory-file-names" "names must be a non-empty list";
          onInvalid =
            _entry: value:
            if !builtins.isList value || value == [ ] then
              labeled subject "directory-file-names" "names must be a non-empty list"
            else
              labeled subject "directory-file-name" "names must contain normalized relative paths";
        };
        representation =
          optionalLabeled subject "directory-file-representation" "representation must be a non-empty string"
            nonEmptyString;
        onConflict =
          optionalLabeled subject "directory-file-conflict-policy"
            "onConflict must be a declared conflict policy"
            declaredPolicy;
        provenance =
          optionalLabeled subject "directory-file-provenance" "provenance must be a string"
            builtins.isString;
      };
    };

  validateSpec =
    spec:
    if !builtins.isAttrs spec then
      checked [
        (problem {
          code = "spec-shape";
          message = "declaration must be an attribute set";
        })
      ] spec
    else
      let
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
          lib.optional (unknownTheme != [ ]) (problem {
            code = "theme-fields";
            message = "theme has unknown fields: ${lib.concatStringsSep ", " unknownTheme}";
          })
          ++ lib.optionals (themeIsAttrs && spec ? theme) (
            lib.optional (!(theme ? id) || !validBaseName theme.id) (problem {
              code = "theme-id";
              message = "theme.id must be a normalized non-empty name";
            })
            ++ lib.optional (hasTemplates && !builtins.isList theme.templates) (problem {
              code = "theme-templates-shape";
              message = "theme.templates must be a list";
            })
            ++ lib.optional (hasTemplates && mixedThemeFields != [ ]) (problem {
              code = "theme-mixed-syntax";
              message = "theme cannot mix templates with single-template fields: ${lib.concatStringsSep ", " mixedThemeFields}";
            })
            ++ builtins.concatMap (
              indexed: themeTemplateErrors "theme.templates[${toString indexed.index}]" indexed.template
            ) (lib.imap0 (index: template: { inherit index template; }) rawTemplates)
          );
        errors = (specSchema spec).diagnostics ++ themeErrors;
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
      indexed: (fileSchema "files[${toString indexed.index}]" indexed.entry).diagnostics
    ) (lib.imap0 (index: entry: { inherit index entry; }) files);

  directoryShapeErrors =
    wrapped: (directorySchema "directories[${toString wrapped.index}]" wrapped.entry).diagnostics;

  directoryRuleErrors =
    wrapped:
    (directoryRuleSchema "directories[${toString wrapped.index}].files" wrapped.entry).diagnostics;

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
              (problem {
                code = "directory-source-kind";
                message = "directory source ${toString current} is not readable as a directory";
              })
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
                    (problem {
                      code = "directory-member-kind";
                      message = "directory source member ${child} must be a regular file or directory, not ${kind}";
                    })
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
        lib.optional (shapeErrors == [ ] && sourceKind == "missing") (problem {
          code = "directory-source-missing";
          message = "src does not exist in the flake source: ${toString entry.src}";
          primary.label = "directories[${toString wrapped.index}]";
          notes = [ "git-backed flakes omit empty and untracked directories" ];
          help = "add a tracked file beneath the directory or remove the declaration";
        })
        ++
          lib.optional (shapeErrors == [ ] && sourceKind != "missing" && sourceKind != "directory")
            (problem {
              code = "directory-source-kind";
              message = "src must be a directory: ${toString entry.src} is ${sourceKind}";
              primary.label = "directories[${toString wrapped.index}]";
            });
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
      duplicateReserved =
        (axiom.registry.compile {
          registrations = reserved;
          keyOf = name: name;
          onDuplicate =
            name: _duplicates:
            problem {
              code = "directory-file-duplicate";
              message = "repeats override name ${name}";
              primary.label = "directories[${toString wrapped.index}]";
            };
        }).diagnostics;
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
        duplicateReserved
        ++ lib.optional (unknownExcluded != [ ]) (problem {
          code = "directory-exclude-unknown";
          message = "excludes unknown names: ${lib.concatStringsSep ", " unknownExcluded}";
          primary.label = "directories[${toString wrapped.index}]";
        })
        ++ lib.optional (unknownReserved != [ ]) (problem {
          code = "directory-file-unknown";
          message = "overrides unknown names: ${lib.concatStringsSep ", " unknownReserved}";
          primary.label = "directories[${toString wrapped.index}]";
        })
        ++ lib.optional (excludedOverrides != [ ]) (problem {
          code = "directory-file-excluded";
          message = "overrides excluded names: ${lib.concatStringsSep ", " excludedOverrides}";
          primary.label = "directories[${toString wrapped.index}]";
        })
        ++ lib.optional (excludedThemes != [ ]) (problem {
          code = "directory-theme-excluded";
          message = "excludes theme sources: ${lib.concatStringsSep ", " excludedThemes}";
          primary.label = "directories[${toString wrapped.index}]";
        })
        ++ lib.optional (themeOverrides != [ ]) (problem {
          code = "directory-file-themed";
          message = "overrides theme sources: ${lib.concatStringsSep ", " themeOverrides}";
          primary.label = "directories[${toString wrapped.index}]";
        });
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
    lib.imap0 (index: entry: {
      name = builtins.toString index;
      value = prewalkDirectory { inherit index entry; };
    }) (spec.directories or [ ])
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
        # matugen renderers only read one config.toml each, so every aspect's
        # entries are tagged with this user context and merged once by the
        # shared runtime before furnish publishes the renderer config.
        matugenThemeEntries = builtins.filter (entry: entry.runtime == "matugen") selected.themeEntries;
        taggedMatugenEntries = builtins.concatMap (
          principal:
          map (
            entry:
            entry
            // {
              inherit principal;
              filesystemNamespace = "${system}/${hostName}";
            }
          ) matugenThemeEntries
        ) principals;
      in
      {
        imports = [
          ./furnish/runtime.nix
          ./program/theme/matugen-runtime.nix
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
            lexicon.theme.matugen.entries = taggedMatugenEntries;
          }
        ]
        ++ lib.optional (spec ? nixos) rawSlice;
      };
}
