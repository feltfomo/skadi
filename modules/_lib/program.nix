# _lib/program.nix lowers one aspect spec into NixOS / Home Manager / hjem
# class modules. ownership rides the spec (hosts/users/exceptHosts/exceptUsers/
# when) and resolves lazily; untagged specs stay global.
{
  lib,
  resolve,
  resolveSystem,
  filePrincipals,
  hostUserNames,
}:
let
  # the file lifecycle layer, reached through the furnish facade like every
  # other furnish surface. it never sees a claim key.
  furnish = import ./furnish { inherit lib resolve resolveSystem; };
  inherit (furnish) contract;
  furnishFiles = furnish.files;

  # keys that mark ownership; everything else is config.
  claimKeys = [
    "hosts"
    "users"
    "exceptHosts"
    "exceptUsers"
    "when"
  ];
  claimKeysAttrs = lib.genAttrs claimKeys (_: null);

  # each files entry is its own leaf so a per-entry claim can drop it.
  entryUnit =
    fieldName: entry:
    if builtins.isAttrs entry then
      (builtins.intersectAttrs claimKeysAttrs entry)
      // {
        ${fieldName} = [ (removeAttrs entry claimKeys) ];
      }
    else
      { ${fieldName} = [ entry ]; };

  # one theme entry, normalized. input_path is never written on the surface; it
  # derives from the placed destination at generation time. subdir is
  # tri-state. absent means "${id}/", null means flat, a string is itself.
  normalizeThemeEntry =
    id: entry:
    let
      source = entry.source or (throw ''program: theme.noctalia.${id} entry is missing "source"'');
      output = entry.output or (throw ''program: theme.noctalia.${id} entry is missing "output"'');
      subdir =
        if !(entry ? subdir) then
          "${id}/"
        else if entry.subdir == null then
          ""
        else
          entry.subdir;
      # baseNameOf keeps the source's store context; a placed name is a name,
      # not a path, and attr names downstream forbid the reference
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
        ;
      reload = entry.reload or null;
      blockId = id;
      registrationId = if subId == null then id else "${id}-${subId}";
    };

  # theme.noctalia as per-entry units, mirroring the files leaf shape so a
  # claim drops an entry's placed file and its registration together. a block
  # with no templates key is sugar for one entry with no subId. block level
  # takes only "id" and "templates"; claims ride each raw entry.
  themeUnits =
    spec:
    let
      block = spec.theme.noctalia or null;
    in
    if block == null then
      [ ]
    else if !builtins.isAttrs block then
      throw "program: theme.noctalia must be an attribute set"
    else
      let
        id = block.id or (throw ''program: theme.noctalia is missing "id"'');
        rawEntries =
          if block ? templates && block ? source then
            throw ''program: theme.noctalia.${id} mixes "templates" with single-entry fields''
          else if block ? templates then
            let
              extra = removeAttrs block [
                "id"
                "templates"
              ];
            in
            if extra != { } then
              throw ''program: theme.noctalia.${id} takes only "id" and "templates" at block level, got ${lib.concatStringsSep ", " (builtins.attrNames extra)}''
            else
              block.templates
          else
            [ (removeAttrs block [ "id" ]) ];
      in
      map (
        raw:
        (builtins.intersectAttrs claimKeysAttrs raw)
        // {
          themeEntries = [ (normalizeThemeEntry id (removeAttrs raw claimKeys)) ];
        }
      ) rawEntries;

  # every file entry and every theme entry is its own root unit under the
  # spec's own claims, so a per-entry claim still drops one before it becomes a
  # declaration. these units resolve through the system door, so an entry
  # naming a user axis is refused there rather than narrowed. that gap is
  # recorded rather than closed, and the refusal is meant to be loud.
  furnishUnit =
    spec:
    (builtins.intersectAttrs claimKeysAttrs spec)
    // {
      children = map (entryUnit "files") (spec.files or [ ]) ++ themeUnits spec;
    };

  # the spec is the root unit; each pkg/import/file/theme entry a child leaf.
  specUnit =
    spec:
    let
      pkg = spec.pkg or null;
      imports = spec.imports or [ ];
    in
    (builtins.intersectAttrs claimKeysAttrs spec)
    // {
      children =
        lib.optional (pkg != null) { inherit pkg; }
        ++ lib.optional (imports != [ ]) { inherit imports; }
        ++ map (entryUnit "files") (spec.files or [ ])
        ++ themeUnits spec;
    };

  # home-manager config for a resolved spec. it is the package and nothing
  # else now. the noctalia templates used to be written here by an activation
  # heredoc, which made home-manager a second authority over destinations
  # furnish is meant to own. they route through the file layer instead.
  hmConfig =
    lib: spec: pkgs:
    (
      let
        pkg = spec.pkg or null;
      in
      lib.mkIf (pkg != null) {
        home.packages = [ (pkg pkgs) ];
      }
    );

  # resolved theme entries become furnish entries, the seed templates plus one
  # registration fragment per block. seeds are writable + runtimeWins because
  # the theme engine rewrites them at runtime, so source-changed-and-disk-
  # changed is the ordinary case rather than drift, and furnish ships the
  # initial content without ever clobbering a rewrite. the fragment is a plain
  # symlink like any generated config, and its store path is forced to a string
  # because a declaration source is plain data. input_path/output_path/
  # post_hook are noctalia's wire names. the surface stays home-relative and
  # the "~/" prefix lands here.
  themeFiles =
    entries: pkgs:
    let
      ids = map (e: e.registrationId) entries;
      # a shared registration id would silently overwrite in the fragment, so
      # name the dup and fail before generating anything.
      dupIds = lib.filter (x: lib.count (y: y == x) ids > 1) (lib.unique ids);
      seedFileOf = e: {
        dest = ".config/noctalia/templates/${e.subdir}${e.placedAs}";
        src = e.source;
        representation = contract.capabilities.writable;
        onConflict = contract.conflictPolicies.runtimeWins;
        provenance = "modules/_lib/program.nix";
      };
      registrationOf =
        e:
        {
          input_path = "~/.config/noctalia/templates/${e.subdir}${e.placedAs}";
          output_path = "~/${e.output}";
        }
        // lib.optionalAttrs (e.reload != null) { post_hook = e.reload; };
      fragmentAttrset = {
        theme.templates.user = builtins.listToAttrs (
          map (e: {
            name = e.registrationId;
            value = registrationOf e;
          }) entries
        );
      };
      inherit ((builtins.head entries)) blockId;
    in
    if entries == [ ] then
      [ ]
    else if dupIds != [ ] then
      throw "program: theme.noctalia.${blockId} has duplicate registration ids: ${lib.concatStringsSep ", " dupIds}"
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
spec:
let
  # home units are the whole spec as one root leaf, with the nixos slice apart.
  homeUnits = [ (specUnit spec) ];
  ownsFiles = (spec.files or [ ]) != [ ] || (spec.theme.noctalia or null) != null;
in
{
  # home slices resolve at user scope from their own host/user args; both default
  # null so an untagged spec resolves globally.
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

  # the hjem slice stays as the class contract's shape while declaring nothing,
  # because furnish is the only authority for these destinations now and two
  # authorities on one path is the thing being prevented.
  hjem = _: {
    files = { };
  };
}
// lib.optionalAttrs (spec ? nixos || ownsFiles) {
  # system slice, emitted when the aspect declares one or when furnish owns one
  # of its file entries. den resolves it once per scope it reaches, so it runs at
  # host scope and again under each user that includes the aspect. both entity
  # args carry defaults, which is what keeps den's class wrapper from dropping
  # the module for naming an arg the scope cannot fill.
  nixos =
    {
      pkgs,
      config,
      host ? null,
      user ? null,
      ...
    }:
    let
      rawSlice = (resolveSystem (spec.nixos { inherit pkgs config; })) { inherit host; };
    in
    if !ownsFiles then
      rawSlice
    else
      let
        hostName = config.networking.hostName;
        inherit (pkgs.stdenv.hostPlatform) system;
        # the same system door the raw half uses, so a per-entry host claim
        # reaches one verdict for both halves. a user-axis claim on one of these
        # entries is refused there.
        resolved = (resolveSystem [ (furnishUnit spec) ]) { inherit host; };
        hostFiles = (resolved.files or [ ]) ++ themeFiles (resolved.themeEntries or [ ]) pkgs;
      in
      {
        # a module that names a furnish option owns the import.
        imports = [
          ./furnish/runtime.nix
          {
            # the file half is delivered per user, so a host where no user
            # received it declares nothing and activates an empty furnish. the
            # check is host-global because a single host-scope emission
            # legitimately contributes zero.
            assertions = lib.optional (hostFiles != [ ]) {
              assertion = config.lexicon.furnish.declarations != [ ];
              message = "furnish: file entries on ${hostName} reached no user principal (have: ${
                lib.concatStringsSep ", " (hostUserNames {
                  inherit system;
                  host = hostName;
                })
              })";
            };
            # on lumi this asked den for every user on the host, and grandpa
            # took 29 declarations for files feltfomo receives.
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
