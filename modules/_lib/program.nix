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
  inherit (furnish) contract;
  furnishFiles = furnish.files;

  claimKeys = [
    "hosts"
    "users"
    "exceptHosts"
    "exceptUsers"
    "when"
  ];
  claimKeysAttrs = lib.genAttrs claimKeys (_: null);

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
        themeIsAttrs = !(spec ? theme) || builtins.isAttrs spec.theme;
        block = if themeIsAttrs then spec.theme.noctalia or null else null;
        blockIsAttrs = block == null || builtins.isAttrs block;
        blockExtra =
          if blockIsAttrs && block != null && block ? templates then
            removeAttrs block [
              "id"
              "templates"
            ]
          else
            { };
        errors =
          lib.optional (spec ? pkg && !builtins.isFunction spec.pkg) (
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
          ++ lib.optional (!themeIsAttrs) (problem "program/theme-shape" "theme must be an attribute set")
          ++ lib.optional (!blockIsAttrs) (
            problem "program/noctalia-shape" "theme.noctalia must be an attribute set"
          )
          ++ lib.optionals (blockIsAttrs && block != null) (
            lib.optional (!(block ? id) || !builtins.isString block.id || block.id == "") (
              problem "program/noctalia-id" "theme.noctalia.id must be a non-empty string"
            )
            ++ lib.optional (block ? templates && !builtins.isList block.templates) (
              problem "program/noctalia-templates-shape" "theme.noctalia.templates must be a list"
            )
            ++ lib.optional (block ? templates && block ? source) (
              problem "program/noctalia-mixed-syntax" "theme.noctalia cannot mix templates with single-entry fields"
            )
            ++ lib.optional (blockExtra != { }) (
              problem "program/noctalia-block-fields" "theme.noctalia with templates accepts only id and templates at block level"
            )
          );
      in
      checked errors spec;

  entryUnit =
    fieldName: entry:
    (if builtins.isAttrs entry then builtins.intersectAttrs claimKeysAttrs entry else { })
    // {
      ${fieldName} = [ (if builtins.isAttrs entry then removeAttrs entry claimKeys else entry) ];
    };

  # theme entries stay descriptive until ownership has selected them.
  themeUnits =
    spec:
    let
      block = spec.theme.noctalia or null;
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
        (if builtins.isAttrs raw then builtins.intersectAttrs claimKeysAttrs raw else { })
        // {
          themeEntries = [
            {
              blockId = id;
              entry = if builtins.isAttrs raw then removeAttrs raw claimKeys else raw;
            }
          ];
        }
      ) rawEntries;

  furnishUnit =
    spec:
    (builtins.intersectAttrs claimKeysAttrs spec)
    // {
      children = map (entryUnit "files") (spec.files or [ ]) ++ themeUnits spec;
    };

  specUnit =
    spec:
    let
      pkg = spec.pkg or null;
      imports = spec.imports or [ ];
    in
    (builtins.intersectAttrs claimKeysAttrs spec)
    // {
      children =
        lib.optional (pkg != null) { inherit pkg; } ++ lib.optional (imports != [ ]) { inherit imports; };
    };

  fileErrors =
    files:
    lib.concatLists (
      lib.imap0 (
        index: entry:
        let
          subject = "files[${toString index}]";
        in
        if !builtins.isAttrs entry then
          [ (problem "program/file-entry-shape" "${subject} must be an attribute set") ]
        else
          lib.optional (!(entry ? dest) || !builtins.isString entry.dest || entry.dest == "") (
            problem "program/file-destination" "${subject}.dest must be a non-empty string"
          )
          ++ lib.optional (!(entry ? src)) (problem "program/file-source" "${subject}.src is required")
          ++ lib.optional (entry ? label && !builtins.isString entry.label) (
            problem "program/file-label" "${subject}.label must be a string"
          )
          ++ lib.optional (entry ? provenance && !builtins.isString entry.provenance) (
            problem "program/file-provenance" "${subject}.provenance must be a string"
          )
          ++ lib.optional (entry ? representation && !builtins.isString entry.representation) (
            problem "program/file-representation" "${subject}.representation must be a string"
          )
          ++ lib.optional (entry ? onConflict && !builtins.isString entry.onConflict) (
            problem "program/file-conflict-policy" "${subject}.onConflict must be a string"
          )
      ) files
    );

  themeEntryErrors =
    themeEntries:
    lib.concatLists (
      lib.imap0 (
        index: wrapped:
        let
          subject = "theme.noctalia.${wrapped.blockId}.templates[${toString index}]";
          inherit (wrapped) entry;
        in
        if !builtins.isAttrs entry then
          [ (problem "program/theme-entry-shape" "${subject} must be an attribute set") ]
        else
          lib.optional (!(entry ? source)) (problem "program/theme-source" "${subject}.source is required")
          ++ lib.optional (!(entry ? output) || !builtins.isString entry.output || entry.output == "") (
            problem "program/theme-output" "${subject}.output must be a non-empty string"
          )
          ++ lib.optional (entry ? subdir && entry.subdir != null && !builtins.isString entry.subdir) (
            problem "program/theme-subdir" "${subject}.subdir must be null or a string"
          )
          ++ lib.optional (entry ? placedAs && !builtins.isString entry.placedAs) (
            problem "program/theme-placed-name" "${subject}.placedAs must be a string"
          )
          ++ lib.optional (entry ? subId && entry.subId != null && !builtins.isString entry.subId) (
            problem "program/theme-sub-id" "${subject}.subId must be null or a string"
          )
          ++ lib.optional (entry ? reload && entry.reload != null && !builtins.isString entry.reload) (
            problem "program/theme-reload" "${subject}.reload must be null or a string"
          )
      ) themeEntries
    );

  normalizeThemeEntry =
    wrapped:
    let
      inherit (wrapped) blockId;
      inherit (wrapped.entry) source output;
      inherit (wrapped) entry;
      subdir =
        if !(entry ? subdir) then
          "${blockId}/"
        else if entry.subdir == null then
          ""
        else
          entry.subdir;
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
        ;
      reload = entry.reload or null;
      registrationId = if subId == null then blockId else "${blockId}-${subId}";
    };

  validateSelected =
    files: themeEntries:
    let
      errors = fileErrors files ++ themeEntryErrors themeEntries;
    in
    checked errors {
      inherit files;
      themeEntries = map normalizeThemeEntry themeEntries;
    };

  hmConfig =
    lib: resolved: pkgs:
    let
      pkg = resolved.pkg or null;
    in
    lib.mkIf (pkg != null) {
      home.packages = [ (pkg pkgs) ];
    };

  themeFiles =
    entries: pkgs:
    let
      ids = map (entry: entry.registrationId) entries;
      dupIds = lib.filter (id: lib.count (candidate: candidate == id) ids > 1) (lib.unique ids);
      seedFileOf = entry: {
        dest = ".config/noctalia/templates/${entry.subdir}${entry.placedAs}";
        src = entry.source;
        representation = contract.capabilities.writable;
        onConflict = contract.conflictPolicies.runtimeWins;
        provenance = "modules/_lib/program.nix";
      };
      registrationOf =
        entry:
        {
          input_path = "~/.config/noctalia/templates/${entry.subdir}${entry.placedAs}";
          output_path = "~/${entry.output}";
        }
        // lib.optionalAttrs (entry.reload != null) { post_hook = entry.reload; };
      fragmentAttrset = {
        theme.templates.user = builtins.listToAttrs (
          map (entry: {
            name = entry.registrationId;
            value = registrationOf entry;
          }) entries
        );
      };
      inherit ((builtins.head entries)) blockId;
    in
    if entries == [ ] then
      [ ]
    else if dupIds != [ ] then
      checked
        [
          (problem "program/theme-registration-duplicate" "theme.noctalia.${blockId} has duplicate registration ids: ${lib.concatStringsSep ", " dupIds}")
        ]
        [ ]
    else
      map seedFileOf entries
      ++ [
        {
          dest = ".config/noctalia/${blockId}.toml";
          src = "${(pkgs.formats.toml { }).generate "noctalia-${blockId}.toml" fragmentAttrset}";
          provenance = "modules/_lib/program.nix";
        }
      ];
in
rawSpec:
let
  spec = validateSpec rawSpec;
  ownsFiles = (spec.files or [ ]) != [ ] || (spec.theme.noctalia or null) != null;
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
        resolved = (resolveSystem [ (furnishUnit spec) ]) { inherit host; };
        selected = validateSelected (resolved.files or [ ]) (resolved.themeEntries or [ ]);
        hostFiles = selected.files ++ themeFiles selected.themeEntries pkgs;
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
