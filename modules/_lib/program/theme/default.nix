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
  axiom = import ../../axiom { inherit lib; };
  capability = import ./capabilities.nix;

  # a capability the adapter declares, rather than a per-feature boolean every
  # adapter has to remember to set
  declares = name: adapter: (axiom.requirements.evaluate [ name ] adapter.capabilities).satisfied;

  entryProblem =
    subject: code: message:
    problem {
      inherit code message;
      primary.label = subject;
    };

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
        # a shell may be assigned by exactly one renderer declaration, which is
        # duplicate keying on the shell name
        overlapErrors =
          (axiom.registry.compile {
            registrations = builtins.filter (
              assignment: builtins.elem assignment.shell themeBackends
            ) assignments;
            keyOf = assignment: assignment.shell;
            onDuplicate =
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
              };
          }).diagnostics;
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
  # closed, because a theme entry's vocabulary is the claim keys plus the value
  # fields and nothing else -- an unknown key here is a typo
  themeEntrySchema =
    subject:
    axiom.schema.compile {
      onRecord = _value: entryProblem subject "theme-entry-shape" "must be an attribute set";
      onUnknown = name: _value: entryProblem subject "theme-entry-fields" "has unknown field ${name}";
      order = themeEntryFields;
      fields = lib.genAttrs claimKeys (_: { }) // {
        source = {
          required = true;
          validate = value: builtins.isPath value || builtins.isString value;
          onMissing = _entry: entryProblem subject "theme-source" "source must be a path or string";
          onInvalid = _entry: _value: entryProblem subject "theme-source" "source must be a path or string";
        };
        output = {
          required = true;
          validate = validRelativePath;
          onMissing = _entry: entryProblem subject "theme-output" "output must be a normalized relative path";
          onInvalid =
            _entry: _value: entryProblem subject "theme-output" "output must be a normalized relative path";
        };
        subdir = {
          validate = value: value == null || validSubdir value;
          onInvalid =
            _entry: _value:
            entryProblem subject "theme-subdir"
              "subdir must be null, empty, or a normalized relative directory";
        };
        placedAs = {
          validate = validBaseName;
          onInvalid =
            _entry: _value: entryProblem subject "theme-placed-name" "placedAs must be a normalized basename";
        };
        subId = {
          validate = value: value == null || validBaseName value;
          onInvalid =
            _entry: _value:
            entryProblem subject "theme-sub-id" "subId must be null or a normalized non-empty name";
        };
        reload = {
          validate = value: value == null || builtins.isString value;
          onInvalid = _entry: _value: entryProblem subject "theme-reload" "reload must be null or a string";
        };
        native = {
          validate = builtins.isAttrs;
          onInvalid = _entry: _value: entryProblem subject "theme-native" "native must be an attribute set";
        };
      };
    };

  themeEntryErrors =
    themeEntries:
    builtins.concatMap (
      indexed:
      let
        inherit (indexed) index wrapped;
        subject = "theme.${wrapped.renderer}.${wrapped.blockId}.templates[${toString index}]";
      in
      (themeEntrySchema subject wrapped.entry).diagnostics
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
      registrationId =
        if subId == null then
          blockId
        else
          axiom.canonical.join "-" [
            blockId
            subId
          ];
      runtime = adapters.${renderer}.runtime or null;
    };

  themeGroupFiles =
    pkgs: entries:
    let
      inherit ((builtins.head entries)) blockId renderer;
      adapter = adapters.${renderer};
      duplicateIds =
        (axiom.registry.compile {
          registrations = entries;
          keyOf = entry: entry.registrationId;
          onDuplicate =
            id: _duplicates:
            problem {
              code = "theme-registration-duplicate";
              message = "has duplicate registration id ${id}";
              primary.label = "theme.${renderer}.${blockId}";
            };
        }).diagnostics;
      unsupportedNativeIds = map (entry: entry.registrationId) (
        builtins.filter (entry: !(declares capability.nativeBlocks adapter) && entry.native != { }) entries
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
    if duplicateIds != [ ] then
      reporter.checked duplicateIds [ ]
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

  # an adapter that declares aggregate-files lowers every selected block
  # together instead of emitting one registration file per block, and owes an
  # aggregateFilesFor alongside the capability
  aggregatedThemeFiles =
    entries: pkgs:
    builtins.concatMap (
      renderer:
      let
        adapter = adapters.${renderer};
      in
      if !(declares capability.aggregateFiles adapter) then
        [ ]
      else
        let
          rendererEntries = builtins.filter (entry: entry.renderer == renderer) entries;
          duplicateIds =
            (axiom.registry.compile {
              registrations = rendererEntries;
              keyOf = entry: entry.registrationId;
              onDuplicate =
                id: _duplicates:
                problem {
                  code = "theme-registration-duplicate";
                  message = "has duplicate registration id ${id} across blocks";
                  primary.label = "theme.${renderer}";
                };
            }).diagnostics;
        in
        if rendererEntries == [ ] then
          [ ]
        else if duplicateIds != [ ] then
          reporter.checked duplicateIds [ ]
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
      builtins.attrValues (
        builtins.groupBy (
          entry:
          axiom.canonical.join ":" [
            entry.renderer
            entry.blockId
          ]
        ) entries
      )
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
