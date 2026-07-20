# _lib/ownerships/merge.nix
#
# Values and their contributing units travel through one shape-keyed recursion.
# Ordinary callers project the merged value; explanations and lock policies can
# inspect the lazy provenance sibling without a second merge implementation.
{ lib }:
let
  inherit (builtins)
    isAttrs
    isList
    head
    tail
    foldl'
    ;

  inherit (import ../krisis { inherit lib; }) safeRender;

  shownPath = path: if path == "" then "<root>" else path;
  contributorIdentities =
    contributors: lib.unique (map (contributor: safeRender contributor.identity) contributors);

  renderConflict =
    path: contributors:
    "ownerships: conflict at ${shownPath path}: co-owners ${lib.concatStringsSep ", " (contributorIdentities contributors)} set differing values";

  renderLockViolation =
    path: contributor:
    "ownerships: single-writer lock violation at ${shownPath path}: foreign contributor ${safeRender contributor.identity}";

  # Equal scalars retain the old result. A difference still throws at the same
  # point, but identifies the contributing units without rendering either
  # arbitrary value.
  strictScalar =
    path: a: b:
    if a.value == b.value then
      a.value
    else
      throw (renderConflict path (a.contributors ++ b.contributors));

  takeRightScalar =
    _path: _a: b:
    b.value;

  builtinStrategies = {
    "ordered-concat" = a: b: a ++ b;
    "dedup-union" = a: b: lib.unique (a ++ b);
    "take-right" = _a: b: b;
  };

  builtinProfiles = {
    "strict-ordered" = {
      listStrategy = "ordered-concat";
      scalarPolicy = strictScalar;
      attrsetTreatment = "deep";
    };
    "last-wins" = {
      listStrategy = "take-right";
      scalarPolicy = takeRightScalar;
      attrsetTreatment = "take-right";
    };
  };

  mkMerge =
    args@{
      strategies ? builtinStrategies,
      listStrategyFor ? (_path: "ordered-concat"),
      conflictPolicy ? strictScalar,
      lockFor ? (_path: null),
      profiles ? builtinProfiles,
      profileForPath ? (_path: null),
    }:
    let
      lockingEnabled = args ? lockFor;
      profilingEnabled = args ? profiles;
      subPath = path: key: if path == "" then key else "${path}.${key}";
      provenanceAttrs = value: isAttrs value && (value.type or null) != "derivation";

      profileNamed =
        path: name:
        if !builtins.isString name then
          throw "ownerships: merge profile name at ${shownPath path} must be a string; got ${builtins.typeOf name}"
        else
          profiles.${name}
            or (throw "ownerships: unknown merge profile ${safeRender name} at ${shownPath path}");

      validateContributorProfile =
        contributor:
        if contributor ? mergeProfile then
          builtins.seq (profileNamed "<unit>" contributor.mergeProfile) true
        else
          true;

      profileDecision =
        path: contributors:
        let
          pathName = profileForPath path;
          names = map (contributor: contributor.mergeProfile or null) contributors;
          explicit = lib.unique (builtins.filter (name: name != null) names);
          mixed = explicit != [ ] && builtins.any (name: name == null) names;
          explicitDisagreement = builtins.length explicit > 1;
          disagreement = explicitDisagreement || mixed;
          selectedName =
            if pathName != null then
              pathName
            else if !disagreement && explicit != [ ] then
              head explicit
            else
              "strict-ordered";
        in
        {
          name = selectedName;
          profile = profileNamed path selectedName;
          unitDisagreement = pathName == null && disagreement;
          unitExplicitDisagreement = pathName == null && explicitDisagreement;
          unitProfiles = explicit;
        };

      renderProfileDisagreement =
        path: decision: contributors:
        "ownerships: merge profile disagreement at ${shownPath path}: contributors ${lib.concatStringsSep ", " (contributorIdentities contributors)} selected incompatible unit profiles ${safeRender decision.unitProfiles}";

      authorize =
        path: contributors:
        let
          predicate = lockFor path;
          foreign =
            if predicate == null then
              [ ]
            else
              builtins.filter (contributor: !(predicate contributor)) contributors;
        in
        if foreign == [ ] then true else throw (renderLockViolation path (head foreign));

      # A branch written by only one input still needs a lazy provenance subtree.
      # With no lockFor argument its value is returned untouched and the subtree
      # isn't walked. An opt-in lock must inspect every descendant so a caller's
      # path policy covers writes below a locked subtree.
      adoptNode =
        path: node:
        let
          children =
            if provenanceAttrs node.value then
              lib.mapAttrs (
                key: value:
                adoptNode (subPath path key) {
                  inherit value;
                  inherit (node) contributors;
                }
              ) node.value
            else
              { };
          provenance = {
            inherit path;
            inherit (node) contributors;
            children = lib.mapAttrs (_: child: child.provenance) children;
          };
          checkedValue =
            if !lockingEnabled && !profilingEnabled then
              node.value
            else
              builtins.seq (if lockingEnabled then authorize path node.contributors else true) (
                builtins.seq (
                  if profilingEnabled then lib.all validateContributorProfile node.contributors else true
                ) (if provenanceAttrs node.value then lib.mapAttrs (_: child: child.value) children else node.value)
              );
        in
        node
        // {
          value = checkedValue;
          inherit provenance;
        };

      # Authorization is the first operation at every node. Scalar equality,
      # list strategy selection, and conflict policy dispatch happen only after
      # every contributor at that path has passed the caller's predicate.
      mergeNode =
        path: a: b:
        let
          contributors = a.contributors ++ b.contributors;
          checked = if lockingEnabled then authorize path contributors else true;
          profilesChecked =
            if profilingEnabled then lib.all validateContributorProfile contributors else true;
          decision = if profilingEnabled then profileDecision path contributors else null;
          listProfile =
            if decision.unitDisagreement then
              throw (renderProfileDisagreement path decision contributors)
            else
              decision.profile;
          scalarProfile =
            if decision.unitExplicitDisagreement then
              throw (renderProfileDisagreement path decision contributors)
            else
              decision.profile;
          attrKeysOverlap = builtins.any (key: b.value ? ${key}) (builtins.attrNames a.value);

          deepMerge =
            let
              keys = lib.attrNames (a.value // b.value);
              children = lib.genAttrs keys (
                key:
                if (a.value ? ${key}) && (b.value ? ${key}) then
                  mergeNode (subPath path key)
                    {
                      value = a.value.${key};
                      inherit (a) contributors;
                    }
                    {
                      value = b.value.${key};
                      inherit (b) contributors;
                    }
                else if a.value ? ${key} then
                  adoptNode (subPath path key) {
                    value = a.value.${key};
                    inherit (a) contributors;
                  }
                else
                  adoptNode (subPath path key) {
                    value = b.value.${key};
                    inherit (b) contributors;
                  }
              );
            in
            {
              value = lib.mapAttrs (_: child: child.value) children;
              inherit contributors;
              provenance = {
                inherit path contributors;
                children = lib.mapAttrs (_: child: child.provenance) children;
              };
            };
        in
        builtins.seq checked (
          builtins.seq profilesChecked (
            if isAttrs a.value && isAttrs b.value then
              if
                profilingEnabled
                && !decision.unitDisagreement
                && decision.profile.attrsetTreatment == "take-right"
                && attrKeysOverlap
              then
                let
                  right = if b ? provenance then b else adoptNode path b;
                in
                {
                  inherit (right) value;
                  inherit contributors;
                  provenance = {
                    inherit path contributors;
                    children = right.provenance.children;
                  };
                }
              else if
                profilingEnabled
                && !builtins.elem decision.profile.attrsetTreatment [
                  "deep"
                  "take-right"
                ]
              then
                throw "ownerships: unknown attrset treatment ${safeRender decision.profile.attrsetTreatment} in merge profile ${safeRender decision.name}"
              else
                deepMerge
            else if isList a.value && isList b.value then
              let
                name = if profilingEnabled then listProfile.listStrategy else listStrategyFor path;
                strategy = strategies.${name} or (throw "ownerships: no merge strategy '${name}' (at ${path})");
              in
              {
                value = strategy a.value b.value;
                inherit contributors;
                # Lists are terminal because their strategy merges the list as a
                # whole. Contributors are ordered leaves, never per-element owners.
                provenance = {
                  inherit path contributors;
                  children = { };
                };
              }
            else
              {
                value = if profilingEnabled then scalarProfile.scalarPolicy path a b else conflictPolicy path a b;
                inherit contributors;
                provenance = {
                  inherit path contributors;
                  children = { };
                };
              }
          )
        );

      mergeTracked =
        entries:
        if entries == [ ] then
          {
            value = { };
            provenance = {
              path = "";
              contributors = [ ];
              children = { };
            };
          }
        else
          let
            tracked = map (
              entry:
              adoptNode "" {
                inherit (entry) value;
                contributors = [ entry.contributor ];
              }
            ) entries;
            merged = foldl' (mergeNode "") (head tracked) (tail tracked);
          in
          {
            inherit (merged) value provenance;
          };

      # Kept for direct low-level callers, but projected from the tracked merge
      # so there is only one shape recursion to maintain. The engine's resolve
      # path uses mergeTracked and never calls these compatibility projections.
      unattributed = {
        identity = "unattributed unit";
        owners = { };
      };
      mergeAll =
        values:
        (mergeTracked (
          map (value: {
            inherit value;
            contributor = unattributed;
          }) values
        )).value;
      mergeTwo =
        path: a: b:
        (mergeNode path
          (adoptNode path {
            value = a;
            contributors = [ unattributed ];
          })
          (
            adoptNode path {
              value = b;
              contributors = [ unattributed ];
            }
          )
        ).value;
    in
    {
      inherit
        mergeTwo
        mergeAll
        mergeTracked
        ;
    };
in
{
  inherit
    builtinStrategies
    builtinProfiles
    strictScalar
    takeRightScalar
    renderConflict
    renderLockViolation
    mkMerge
    ;
}
