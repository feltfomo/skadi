{
  lib,
  contract,
  claimKeys,
  claimsOf,
  withoutClaims,
  unknownFields,
  validRelativePath,
  validBaseName,
  validSubdir,
  duplicateValues,
  problem,
  checked,
}:
let
  adapters = {
    caelestia = import ./adapters/caelestia.nix { inherit lib; };
    dms = import ./adapters/dms.nix { inherit lib; };
    noctalia = import ./adapters/noctalia.nix { inherit lib; };
  };
  themeBackends = builtins.attrNames adapters;
  themeSharedFields = claimKeys ++ [
    "source"
    "output"
    "subdir"
    "placedAs"
    "subId"
    "reload"
  ];
  themeRendererFields = themeSharedFields ++ [ "native" ];
  themeFields = themeSharedFields ++ [
    "id"
    "renderers"
    "templates"
  ];
  themeEntryFields = themeRendererFields;
  themeTemplateErrors =
    subject: template:
    if !builtins.isAttrs template then
      [ (problem "program/theme-template-shape" "${subject} must be an attribute set") ]
    else
      let
        unknownTemplate = unknownFields (themeSharedFields ++ [ "renderers" ]) template;
        renderers =
          if template ? renderers && builtins.isAttrs template.renderers then template.renderers else { };
        rendererNames = builtins.attrNames renderers;
        unknownRenderers = builtins.filter (name: !(builtins.elem name themeBackends)) rendererNames;
        rendererErrors = builtins.concatMap (
          renderer:
          let
            override = renderers.${renderer};
            unknownOverride =
              if builtins.isAttrs override then unknownFields themeRendererFields override else [ ];
          in
          lib.optional (!builtins.isAttrs override) (
            problem "program/theme-renderer-shape" "${subject}.renderers.${renderer} must be an attribute set"
          )
          ++ lib.optionals (builtins.isAttrs override) (
            lib.optional (unknownOverride != [ ]) (
              problem "program/theme-renderer-fields" "${subject}.renderers.${renderer} has unknown fields: ${lib.concatStringsSep ", " unknownOverride}"
            )
          )
        ) rendererNames;
      in
      lib.optional (unknownTemplate != [ ]) (
        problem "program/theme-template-fields" "${subject} has unknown fields: ${lib.concatStringsSep ", " unknownTemplate}"
      )
      ++ lib.optional (!(template ? renderers) || !builtins.isAttrs template.renderers) (
        problem "program/theme-renderers-shape" "${subject}.renderers must be an attribute set"
      )
      ++ lib.optional (
        template ? renderers && builtins.isAttrs template.renderers && rendererNames == [ ]
      ) (problem "program/theme-renderers-empty" "${subject}.renderers must select at least one renderer")
      ++ lib.optional (unknownRenderers != [ ]) (
        problem "program/theme-renderers-unknown" "${subject}.renderers has unknown renderers: ${lib.concatStringsSep ", " unknownRenderers}"
      )
      ++ rendererErrors;

  elaborateTheme =
    theme:
    let
      rawTemplates =
        theme.templates or [
          (removeAttrs theme [
            "id"
            "templates"
          ])
        ];
      entriesFor =
        renderer:
        builtins.concatMap (
          template:
          if
            builtins.isAttrs template
            && builtins.isAttrs (template.renderers or null)
            && builtins.hasAttr renderer template.renderers
          then
            [
              ((removeAttrs template [ "renderers" ]) // template.renderers.${renderer})
            ]
          else
            [ ]
        ) rawTemplates;
    in
    lib.filterAttrs (_: block: block.templates != [ ]) (
      lib.genAttrs themeBackends (renderer: {
        inherit (theme) id;
        templates = entriesFor renderer;
      })
    );

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

  themeGroupFiles =
    pkgs: entries:
    let
      inherit ((builtins.head entries)) blockId renderer;
      adapter = adapters.${renderer};
      ids = map (entry: entry.registrationId) entries;
      dupIds = duplicateValues ids;
      unsupportedNativeIds = map (entry: entry.registrationId) (
        builtins.filter (entry: !adapter.acceptsNative && entry.native != { }) entries
      );
      inherit (adapter) templateNameOf;
      seedFileOf = entry: {
        dest = "${adapter.templateRoot}/${templateNameOf entry}";
        src = entry.source;
        representation = contract.capabilities.writable;
        onConflict = contract.conflictPolicies.runtimeWins;
        provenance = "modules/_lib/program.nix";
      };
    in
    if dupIds != [ ] then
      checked
        [
          (problem "program/theme-registration-duplicate" "theme.${renderer}.${blockId} has duplicate registration ids: ${lib.concatStringsSep ", " dupIds}")
        ]
        [ ]
    else if unsupportedNativeIds != [ ] then
      checked
        [
          (problem "program/theme-native-unsupported" "theme.${renderer}.${blockId} cannot use native registration fields: ${lib.concatStringsSep ", " unsupportedNativeIds}")
        ]
        [ ]
    else
      map seedFileOf entries
      ++ adapter.filesFor {
        inherit
          pkgs
          blockId
          entries
          templateNameOf
          ;
      };

  themeFiles =
    entries: pkgs:
    builtins.concatMap (themeGroupFiles pkgs) (
      builtins.attrValues (builtins.groupBy (entry: "${entry.renderer}:${entry.blockId}") entries)
    );
in
{
  inherit
    themeBackends
    themeSharedFields
    themeEntryErrors
    themeFields
    themeFiles
    themeTemplateErrors
    themeUnits
    ;
  elaborate = elaborateTheme;
  normalizeEntry = normalizeThemeEntry;
}
