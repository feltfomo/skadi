# _lib/program.nix -- lowers one aspect spec into NixOS / Home Manager / hjem
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

  # each files/templates entry is its own leaf so a per-entry claim can drop it.
  entryUnit =
    fieldName: entry:
    if builtins.isAttrs entry then
      (builtins.intersectAttrs claimKeysAttrs entry)
      // {
        ${fieldName} = [ (removeAttrs entry claimKeys) ];
      }
    else
      { ${fieldName} = [ entry ]; };

  # every file entry and the serialised noctalia config are their own root unit
  # under the spec's own claims, so a per-entry claim still drops one before it
  # becomes a declaration. these units resolve through the system door, so an
  # entry naming a user axis is refused there rather than narrowed -- a gap that
  # is recorded rather than closed, and the refusal is meant to be loud.
  furnishUnit =
    spec:
    let
      noctaliaConfig = spec.noctaliaConfig or { };
    in
    (builtins.intersectAttrs claimKeysAttrs spec)
    // {
      children =
        map (entryUnit "files") (spec.files or [ ])
        ++ map (entryUnit "templates") (spec.templates or [ ])
        ++ lib.optional (noctaliaConfig != { }) { inherit noctaliaConfig; };
    };

  # the spec is the root unit; each pkg/import/file/template entry a child leaf.
  specUnit =
    spec:
    let
      pkg = spec.pkg or null;
      imports = spec.imports or [ ];
      noctaliaConfig = spec.noctaliaConfig or { };
    in
    (builtins.intersectAttrs claimKeysAttrs spec)
    // {
      children =
        lib.optional (pkg != null) { inherit pkg; }
        ++ lib.optional (imports != [ ]) { inherit imports; }
        ++ lib.optional (noctaliaConfig != { }) { inherit noctaliaConfig; }
        ++ map (entryUnit "files") (spec.files or [ ])
        ++ map (entryUnit "templates") (spec.templates or [ ]);
    };

  # home-manager config for a resolved spec. it is the package and nothing
  # else now: the noctalia templates used to be written here by an activation
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

  # the noctalia templates as writable file entries. the theming engine rewrites
  # these at runtime, so source-changed-and-disk-changed is the ordinary case
  # rather than drift, and the default error policy would refuse activation on
  # every theme change. furnish ships the initial content and never clobbers a
  # rewrite.
  templateFiles =
    spec:
    map (t: {
      dest = ".config/noctalia/templates/${t.subdir or ""}${t.name}";
      src = t.templateFile;
      representation = contract.capabilities.writable;
      onConflict = contract.conflictPolicies.runtimeWins;
      provenance = "modules/_lib/program.nix";
    }) (spec.templates or [ ]);

  # the serialised noctalia config as a file entry, so the generated path and
  # the checked-in paths reach furnish the same way. the store path is forced to
  # a string because a declaration source is plain data.
  noctaliaFiles =
    spec: pkgs:
    let
      noctaliaConfig = spec.noctaliaConfig or { };
    in
    lib.optional (noctaliaConfig != { }) {
      dest = ".config/noctalia/${noctaliaConfig._fileName}.toml";
      src = "${(pkgs.formats.toml { }).generate "noctalia-${noctaliaConfig._fileName}.toml" (
        removeAttrs noctaliaConfig [ "_fileName" ]
      )}";
      provenance = "modules/_lib/program.nix";
    };
in
spec:
let
  # home units are the whole spec as one root leaf, with the nixos slice apart.
  homeUnits = [ (specUnit spec) ];
  ownsFiles =
    (spec.files or [ ]) != [ ] || (spec.templates or [ ]) != [ ] || (spec.noctaliaConfig or { }) != { };
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
        hostFiles = (resolved.files or [ ]) ++ templateFiles resolved ++ noctaliaFiles resolved pkgs;
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
            # the emission declares for the one user den resolved it under. den
            # v0.17.0 fx/policy/schema.nix decomposeSchemaEffect puts aspects a
            # host delivers to its users under the user scope, so the narrowing
            # is delivery rather than a name match, first-wins on a per-context
            # key whose granularity changes with the user count.
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
