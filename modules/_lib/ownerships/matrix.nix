# _lib/ownerships/matrix.nix
#
# read-only fleet projection over the same compose, checks, and selection boundaries used
# by resolution. reports retain names and shallow shape only; config values
# never cross this boundary.
{ lib }:
let
  engine = import ./engine.nix { inherit lib; };
  inherit (import ../krisis { inherit lib; }) safeShape;

  leafKey = index: "leaf-${toString index}";

  projectLeaf = entry: {
    inherit (entry) key;
    identity = engine.identifyUnit {
      unit = entry.leaf.value;
      label = entry.leaf.label or null;
      source = entry.leaf.source or null;
    };
    shape = safeShape entry.leaf.value;
  };

  projectDiagnostic =
    diagnostic:
    {
      inherit (diagnostic) kind reason;
    }
    // lib.optionalAttrs (diagnostic ? axis) { inherit (diagnostic) axis; }
    // lib.optionalAttrs (diagnostic ? axes) { inherit (diagnostic) axes; };

  indexedLeaves =
    leaves:
    builtins.genList (
      index:
      let
        leaf = builtins.elemAt leaves index;
      in
      {
        key = leafKey index;
        inherit leaf;
      }
    ) (builtins.length leaves);

  classify =
    registry: stages: leaves:
    let
      entries = map (
        entry:
        let
          diagnostics = engine.stageDiagnostics "leaf" stages {
            inherit registry;
            leaves = [ entry.leaf ];
          };
        in
        entry
        // {
          impossible = builtins.filter (diagnostic: diagnostic.kind or null == "impossible") diagnostics;
          other = builtins.filter (diagnostic: diagnostic.kind or null != "impossible") diagnostics;
        }
      ) (indexedLeaves leaves);
      otherDiagnostics = builtins.concatMap (entry: entry.other) entries;
    in
    if otherDiagnostics == [ ] then entries else throw (engine.renderDiags otherDiagnostics);

  mkUserContexts =
    {
      roster,
      # hostName is the canonical host id; bind host.id so memberOf reads it
      # directly rather than re-deriving a system prefix from a bare name.
      contextFor ? (
        { hostName, userName }: {
          host.id = hostName;
          user.name = userName;
        }
      ),
    }:
    builtins.concatMap (
      hostName:
      map (userName: {
        key = "${hostName}/${userName}";
        inherit hostName userName;
        ctx = contextFor { inherit hostName userName; };
      }) (roster.membership.${hostName} or [ ])
    ) roster.hosts;

  mkSystemContexts =
    {
      roster,
      contextFor ? ({ hostName }: { host.id = hostName; }),
    }:
    map (hostName: {
      key = hostName;
      inherit hostName;
      ctx = contextFor { inherit hostName; };
    }) roster.hosts;

  report =
    {
      registry,
      stages,
      roster,
      contexts,
      unit,
      scope,
    }:
    let
      composed = engine.compose registry unit;
      classified = classify registry stages composed;
      classifiedParts = builtins.partition (entry: entry.impossible != [ ]) classified;
      deadEntries = classifiedParts.right;
      liveEntries = classifiedParts.wrong;
      treeDiagnostics = engine.stageDiagnostics "tree" stages {
        inherit registry;
        leaves = map (entry: entry.leaf) liveEntries;
      };
      liveLeaves =
        if treeDiagnostics == [ ] then
          map (entry: entry.leaf) liveEntries
        else
          throw (engine.renderDiags treeDiagnostics);

      selectionFor =
        context:
        let
          selected = engine.selectPrepared {
            inherit registry stages;
            inherit (context) ctx;
          } liveLeaves;
        in
        builtins.genList (
          index:
          let
            entry = builtins.elemAt liveEntries index;
            selection = builtins.elemAt selected.selectionTrace index;
          in
          {
            inherit (entry) key;
            inherit (selection) selected rejectedBy;
            offeredPaths = if selection.selected then selection.preMergeContribution.offeredPaths else [ ];
          }
        ) (builtins.length liveEntries);

      selectionsByContext = map (context: {
        inherit context;
        selections = selectionFor context;
      }) contexts;

      contextEntries = map (
        entry:
        let
          inherit (entry) context selections;
          selected = builtins.filter (selection: selection.selected) selections;
        in
        {
          inherit (context) key hostName;
          survivors = map (selection: selection.key) selected;
          inactive = map (selection: {
            inherit (selection) key rejectedBy;
          }) (builtins.filter (selection: !selection.selected) selections);
          preMergePaths = lib.unique (builtins.concatMap (selection: selection.offeredPaths) selected);
        }
        // lib.optionalAttrs (context ? userName) { inherit (context) userName; }
      ) selectionsByContext;

      byContext = builtins.listToAttrs (
        map (entry: {
          name = entry.key;
          value = removeAttrs entry [ "key" ];
        }) contextEntries
      );

      unitSelections = builtins.groupBy (selection: selection.unit) (
        builtins.concatMap (
          entry:
          map (unit: {
            inherit unit;
            context = entry.key;
          }) entry.survivors
        ) contextEntries
      );
      selectedIn = key: map (selection: selection.context) (unitSelections.${key} or [ ]);
      selectedSomewhere = key: selectedIn key != [ ];

      pathSelections = builtins.groupBy (selection: selection.path) (
        builtins.concatMap (
          entry:
          map (path: {
            inherit path;
            context = entry.key;
          }) entry.preMergePaths
        ) contextEntries
      );
      allPaths = lib.unique (builtins.concatMap (entry: entry.preMergePaths) contextEntries);
      pathSelectedIn = path: map (selection: selection.context) (pathSelections.${path} or [ ]);

      coverage = {
        units = builtins.listToAttrs (
          map (entry: {
            name = entry.key;
            value = selectedIn entry.key;
          }) classified
        );
        preMerge = {
          meaning = "top-level paths offered by surviving leaves before merge";
          paths = builtins.listToAttrs (
            map (path: {
              name = path;
              value = pathSelectedIn path;
            }) allPaths
          );
        };
      };

      ownedOnHost =
        field: hostName:
        lib.unique (
          builtins.concatMap (entry: entry.${field}) (
            builtins.filter (entry: entry.hostName == hostName) contextEntries
          )
        );
      hostPairs = builtins.concatMap (
        left: map (right: { inherit left right; }) (builtins.filter (right: left < right) roster.hosts)
      ) roster.hosts;
      diffFor =
        field: pair:
        let
          left = ownedOnHost field pair.left;
          right = ownedOnHost field pair.right;
        in
        {
          leftOnly = builtins.filter (item: !(builtins.elem item right)) left;
          rightOnly = builtins.filter (item: !(builtins.elem item left)) right;
        };
      hostDiffs = builtins.listToAttrs (
        map (pair: {
          name = "${pair.left} -> ${pair.right}";
          value = {
            units = diffFor "survivors" pair;
            preMergePaths = diffFor "preMergePaths" pair;
          };
        }) hostPairs
      );

      unknownUsers = roster.usersWithUnknownMembership or [ ];
      possiblyUnknown =
        entry:
        if scope != "user" || unknownUsers == [ ] || !(registry ? user) then
          false
        else
          let
            claim = entry.leaf.claim.user;
            observation = registry.user.observe claim;
          in
          !(registry.user.isTop claim)
          && builtins.any (userName: builtins.elem userName observation.materializedMembers) unknownUsers;
      indeterminateEntries = builtins.filter (
        entry: !selectedSomewhere entry.key && possiblyUnknown entry
      ) liveEntries;

      # unknown membership explains non-selection more specifically than generic
      # dormancy, so indeterminate entries never appear in this list.
      neverSelectedInModeledContexts = map (
        entry:
        (projectLeaf entry)
        // {
          rejections = builtins.listToAttrs (
            map (contextEntry: {
              name = contextEntry.context.key;
              value =
                (builtins.head (builtins.filter (selection: selection.key == entry.key) contextEntry.selections))
                .rejectedBy;
            }) selectionsByContext
          );
        }
      ) (builtins.filter (entry: !selectedSomewhere entry.key && !(possiblyUnknown entry)) liveEntries);
    in
    {
      units = builtins.listToAttrs (
        map (entry: {
          name = entry.key;
          value = projectLeaf entry;
        }) classified
      );
      inherit
        byContext
        coverage
        hostDiffs
        neverSelectedInModeledContexts
        ;
      # keys throughout are canonical ids; the display map lets a reader recover
      # the human-facing bare host/user names from those canonical ids.
      display = roster.display or { };
      dead = map (
        entry:
        (projectLeaf entry)
        // {
          reasons = map projectDiagnostic entry.impossible;
        }
      ) deadEntries;
      indeterminate = {
        unknownMembershipUsers = unknownUsers;
        units = map projectLeaf indeterminateEntries;
      };
    };
in
{
  inherit
    mkUserContexts
    mkSystemContexts
    report
    ;
}
