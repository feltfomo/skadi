# _lib/ownerships/matrix.nix
#
# Read-only fleet projection over the same compose, checks, and trace path used
# by resolution. Reports retain names and shallow shape only; config values
# never cross this boundary.
{ lib }:
let
  engine = import ./engine.nix { inherit lib; };
  inherit (import ./safe-render.nix { inherit lib; }) safeShape;

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
      contextFor ? (
        { hostName, userName }: {
          host.name = hostName;
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
      contextFor ? ({ hostName }: { host.name = hostName; }),
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
      merge,
      roster,
      contexts,
      unit,
      scope,
    }:
    let
      composed = engine.compose registry unit;
      classified = classify registry stages composed;
      deadEntries = builtins.filter (entry: entry.impossible != [ ]) classified;
      liveEntries = builtins.filter (entry: entry.impossible == [ ]) classified;
      liveForest = {
        children = map (entry: entry.leaf) liveEntries;
      };

      selectionFor =
        context:
        let
          traced = engine.trace {
            inherit registry stages merge;
            inherit (context) ctx;
          } liveForest;
        in
        builtins.genList (
          index:
          let
            entry = builtins.elemAt liveEntries index;
            selection = builtins.elemAt traced.trace index;
          in
          {
            inherit (entry) key;
            inherit (selection) selected rejectedBy;
            offeredPaths = if selection.selected then selection.preMergeContribution.offeredPaths else [ ];
          }
        ) (builtins.length liveEntries);

      contextEntries = map (
        context:
        let
          selections = selectionFor context;
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
      ) contexts;

      byContext = builtins.listToAttrs (
        map (entry: {
          name = entry.key;
          value = removeAttrs entry [ "key" ];
        }) contextEntries
      );

      selectedIn =
        key:
        map (entry: entry.key) (builtins.filter (entry: builtins.elem key entry.survivors) contextEntries);
      selectedSomewhere = key: selectedIn key != [ ];

      allPaths = lib.unique (builtins.concatMap (entry: entry.preMergePaths) contextEntries);
      pathSelectedIn =
        path:
        map (entry: entry.key) (
          builtins.filter (entry: builtins.elem path entry.preMergePaths) contextEntries
        );

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

      neverSelectedInModeledContexts = map (
        entry:
        (projectLeaf entry)
        // {
          rejections = builtins.listToAttrs (
            map (context: {
              name = context.key;
              value =
                (builtins.head (builtins.filter (selection: selection.key == entry.key) (selectionFor context)))
                .rejectedBy;
            }) contexts
          );
        }
      ) (builtins.filter (entry: !selectedSomewhere entry.key) liveEntries);
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
