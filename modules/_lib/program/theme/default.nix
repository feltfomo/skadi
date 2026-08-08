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
  reporter,
}:
let
  adapters = {
    caelestia = import ./adapters/caelestia.nix { inherit lib; };
    dms = import ./adapters/dms.nix { inherit lib; };
    end4-pc = import ./adapters/end4-pc.nix { inherit lib; };
    illogical-impulse = import ./adapters/illogical-impulse.nix { inherit lib; };
    noctalia = import ./adapters/noctalia.nix { inherit lib; };
  };
  themeBackends = builtins.attrNames adapters;
  themeValueFields = [
    "source"
    "output"
    "subdir"
    "placedAs"
    "subId"
    "reload"
    "native"
  ];
  themeSharedFields = claimKeys ++ themeValueFields;
  themeRendererFields = themeSharedFields ++ [ "sharedWith" ];
  themeFields =
    claimKeys
    ++ [
      "id"
      "renderers"
      "templates"
    ]
    ++ themeValueFields;
  themeEntryFields = themeSharedFields;

  knownShellsNote = "known shells: ${lib.concatStringsSep ", " themeBackends}";

  editDistance =
    left: right:
    let
      leftChars = lib.stringToCharacters left;
      rightChars = lib.stringToCharacters right;
      rightLength = builtins.length rightChars;
      initialRow = lib.range 0 rightLength;
      nextRow =
        previous: indexed:
        if rightLength == 0 then
          [ (indexed.index + 1) ]
        else
          lib.foldl' (
            row: rightIndex:
            let
              insertion = lib.last row + 1;
              deletion = builtins.elemAt previous (rightIndex + 1) + 1;
              substitution =
                builtins.elemAt previous rightIndex
                + (if indexed.char == builtins.elemAt rightChars rightIndex then 0 else 1);
            in
            row ++ [ (lib.min insertion (lib.min deletion substitution)) ]
          ) [ (indexed.index + 1) ] (lib.range 0 (rightLength - 1));
      finalRow = lib.foldl' nextRow initialRow (
        lib.imap0 (index: char: { inherit index char; }) leftChars
      );
    in
    lib.last finalRow;

  nearestShell =
    value:
    let
      scored = map (name: {
        inherit name;
        distance = editDistance value name;
      }) themeBackends;
      nearest = lib.foldl' (
        best: candidate: if candidate.distance < best.distance then candidate else best
      ) (builtins.head scored) (builtins.tail scored);
    in
    if nearest.distance <= 2 then nearest.name else null;

  unknownShellProblem =
    subject: shell:
    let
      suggestion = nearestShell shell;
    in
    problem (
      {
        code = "theme-renderer-unknown";
        message = "unknown shell \"${shell}\"";
        primary.label = subject;
        notes = [ knownShellsNote ];
      }
      // lib.optionalAttrs (suggestion != null) { help = "did you mean \"${suggestion}\"?"; }
    );

  sharedShellsOf =
    override:
    if builtins.isAttrs override && override ? sharedWith && builtins.isList override.sharedWith then
      builtins.filter builtins.isString override.sharedWith
    else
      [ ];

  targetsForRenderer = renderer: override: lib.unique ([ renderer ] ++ sharedShellsOf override);
  themeTemplateErrors =
    subject: template:
    if !builtins.isAttrs template then
      [
        (problem {
          code = "theme-template-shape";
          message = "must be an attribute set";
          primary.label = subject;
        })
      ]
    else
      let
        unknownTemplate = unknownFields (themeSharedFields ++ [ "renderers" ]) template;
        renderers =
          if template ? renderers && builtins.isAttrs template.renderers then template.renderers else { };
        rendererNames = builtins.attrNames renderers;
        unknownRendererErrors = map (
          renderer: unknownShellProblem "${subject}.renderers.${renderer}" renderer
        ) (builtins.filter (name: !(builtins.elem name themeBackends)) rendererNames);
        rendererErrors = builtins.concatMap (
          renderer:
          let
            override = renderers.${renderer};
            rendererSubject = "${subject}.renderers.${renderer}";
            unknownOverride =
              if builtins.isAttrs override then unknownFields themeRendererFields override else [ ];
            sharedWith = if builtins.isAttrs override then override.sharedWith or [ ] else [ ];
            sharedIsList = builtins.isList sharedWith;
            sharedStrings = if sharedIsList then builtins.filter builtins.isString sharedWith else [ ];
            duplicateShared = duplicateValues sharedStrings;
            unknownShared = builtins.filter (name: !(builtins.elem name themeBackends)) sharedStrings;
            effective =
              (removeAttrs template [ "renderers" ])
              // (if builtins.isAttrs override then removeAttrs override [ "sharedWith" ] else { });
          in
          lib.optional (!builtins.isAttrs override) (problem {
            code = "theme-renderer-shape";
            message = "must be an attribute set";
            primary.label = rendererSubject;
          })
          ++ lib.optionals (builtins.isAttrs override) (
            lib.optional (unknownOverride != [ ]) (problem {
              code = "theme-renderer-fields";
              message = "has unknown fields: ${lib.concatStringsSep ", " unknownOverride}";
              primary.label = rendererSubject;
            })
            ++ lib.optional (!sharedIsList) (problem {
              code = "theme-renderer-shared-shape";
              message = "sharedWith must be a list of shell names";
              primary.label = "${rendererSubject}.sharedWith";
            })
            ++
              lib.optional (sharedIsList && builtins.length sharedStrings != builtins.length sharedWith)
                (problem {
                  code = "theme-renderer-shared-name";
                  message = "sharedWith must contain only shell-name strings";
                  primary.label = "${rendererSubject}.sharedWith";
                })
            ++ lib.optional (duplicateShared != [ ]) (problem {
              code = "theme-renderer-shared-duplicate";
              message = "sharedWith repeats shells: ${lib.concatStringsSep ", " duplicateShared}";
              primary.label = "${rendererSubject}.sharedWith";
            })
            ++ lib.optional (builtins.elem renderer sharedStrings) (problem {
              code = "theme-renderer-shared-self";
              message = "a renderer cannot share with itself";
              primary.label = "${rendererSubject}.sharedWith";
            })
            ++ map (shell: unknownShellProblem "${rendererSubject}.sharedWith" shell) unknownShared
            ++ lib.optional (!(effective ? source) || !(effective ? output)) (problem {
              code = "theme-renderer-incomplete";
              message = "effective renderer settings must define source and output";
              primary.label = rendererSubject;
            })
          )
        ) rendererNames;
        assignments = builtins.concatMap (
          renderer:
          map (shell: { inherit renderer shell; }) (targetsForRenderer renderer renderers.${renderer})
        ) rendererNames;
        assignmentGroups = builtins.groupBy (assignment: assignment.shell) assignments;
        overlappingAssignments = lib.filterAttrs (
          shell: owners: builtins.elem shell themeBackends && builtins.length owners > 1
        ) assignmentGroups;
        overlapErrors = lib.mapAttrsToList (
          shell: owners:
          let
            ownerNames = map (owner: owner.renderer) owners;
            firstOwner = builtins.head ownerNames;
          in
          problem {
            code = "theme-renderer-overlap";
            message = "shell ${shell} is assigned by multiple renderer declarations";
            primary.label = "${subject}.renderers.${firstOwner}";
            secondaryLabels = map (owner: {
              label = "${subject}.renderers.${owner}";
              message = "also assigns ${shell}";
            }) (builtins.tail ownerNames);
            help = "keep ${shell} in exactly one renderer declaration";
          }
        ) overlappingAssignments;
      in
      lib.optional (unknownTemplate != [ ]) (problem {
        code = "theme-template-fields";
        message = "has unknown fields: ${lib.concatStringsSep ", " unknownTemplate}";
        primary.label = subject;
      })
      ++ lib.optional (!(template ? renderers) || !builtins.isAttrs template.renderers) (problem {
        code = "theme-renderers-shape";
        message = "renderers must be an attribute set";
        primary.label = subject;
      })
      ++
        lib.optional (template ? renderers && builtins.isAttrs template.renderers && rendererNames == [ ])
          (problem {
            code = "theme-renderers-empty";
            message = "renderers must select at least one renderer";
            primary.label = subject;
          })
      ++ unknownRendererErrors
      ++ rendererErrors
      ++ overlapErrors;

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
          if builtins.isAttrs template && builtins.isAttrs (template.renderers or null) then
            builtins.concatMap (
              declaredRenderer:
              let
                override = template.renderers.${declaredRenderer};
                matches = builtins.elem renderer (targetsForRenderer declaredRenderer override);
              in
              lib.optional matches (
                (removeAttrs template [ "renderers" ]) // (removeAttrs override [ "sharedWith" ])
              )
            ) (builtins.attrNames template.renderers)
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
        [
          (problem {
            code = "theme-entry-shape";
            message = "must be an attribute set";
            primary.label = subject;
          })
        ]
      else
        lib.optional (unknown != [ ]) (problem {
          code = "theme-entry-fields";
          message = "has unknown fields: ${lib.concatStringsSep ", " unknown}";
          primary.label = subject;
        })
        ++
          lib.optional
            (!(entry ? source) || !(builtins.isPath entry.source || builtins.isString entry.source))
            (problem {
              code = "theme-source";
              message = "source must be a path or string";
              primary.label = subject;
            })
        ++ lib.optional (!(entry ? output) || !validRelativePath entry.output) (problem {
          code = "theme-output";
          message = "output must be a normalized relative path";
          primary.label = subject;
        })
        ++ lib.optional (entry ? subdir && entry.subdir != null && !validSubdir entry.subdir) (problem {
          code = "theme-subdir";
          message = "subdir must be null, empty, or a normalized relative directory";
          primary.label = subject;
        })
        ++ lib.optional (entry ? placedAs && !validBaseName entry.placedAs) (problem {
          code = "theme-placed-name";
          message = "placedAs must be a normalized basename";
          primary.label = subject;
        })
        ++ lib.optional (entry ? subId && entry.subId != null && !validBaseName entry.subId) (problem {
          code = "theme-sub-id";
          message = "subId must be null or a normalized non-empty name";
          primary.label = subject;
        })
        ++
          lib.optional (entry ? reload && entry.reload != null && !builtins.isString entry.reload)
            (problem {
              code = "theme-reload";
              message = "reload must be null or a string";
              primary.label = subject;
            })
        ++ lib.optional (entry ? native && !builtins.isAttrs entry.native) (problem {
          code = "theme-native";
          message = "native must be an attribute set";
          primary.label = subject;
        })
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
      runtime = adapters.${renderer}.runtime or null;
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
      reporter.checked
        [
          (problem {
            code = "theme-registration-duplicate";
            message = "has duplicate registration ids: ${lib.concatStringsSep ", " dupIds}";
            primary.label = "theme.${renderer}.${blockId}";
          })
        ]
        [ ]
    else if unsupportedNativeIds != [ ] then
      reporter.checked
        [
          (problem {
            code = "theme-native-unsupported";
            message = "cannot use native registration fields: ${lib.concatStringsSep ", " unsupportedNativeIds}";
            primary.label = "theme.${renderer}.${blockId}";
          })
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

  # backends with their own aggregateFilesFor can lower every selected block
  # together instead of emitting one registration file per block.
  aggregatedThemeFiles =
    entries: pkgs:
    builtins.concatMap (
      renderer:
      let
        adapter = adapters.${renderer};
      in
      if !(adapter ? aggregateFilesFor) then
        [ ]
      else
        let
          rendererEntries = builtins.filter (entry: entry.renderer == renderer) entries;
          ids = map (entry: entry.registrationId) rendererEntries;
          dupIds = duplicateValues ids;
        in
        if rendererEntries == [ ] then
          [ ]
        else if dupIds != [ ] then
          reporter.checked
            [
              (problem {
                code = "theme-registration-duplicate";
                message = "has duplicate registration ids across blocks: ${lib.concatStringsSep ", " dupIds}";
                primary.label = "theme.${renderer}";
              })
            ]
            [ ]
        else
          adapter.aggregateFilesFor {
            inherit pkgs;
            entries = rendererEntries;
            registrationOf = adapter.registrationOf or (entry: entry.native);
          }
    ) themeBackends;

  themeFiles =
    entries: pkgs:
    builtins.concatMap (themeGroupFiles pkgs) (
      builtins.attrValues (builtins.groupBy (entry: "${entry.renderer}:${entry.blockId}") entries)
    )
    ++ aggregatedThemeFiles entries pkgs;
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
