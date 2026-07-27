# _lib/program.nix -- lowers one aspect spec into NixOS / Home Manager / hjem
# class modules. ownership rides the spec (hosts/users/exceptHosts/exceptUsers/
# when) and resolves lazily; untagged specs stay global.
{
  lib,
  resolve,
  resolveSystem,
  hostPrincipals,
}:
let
  # the file lifecycle layer, reached through the furnish facade like every
  # other furnish surface. it never sees a claim key.
  furnishFiles = (import ./furnish { inherit lib resolve resolveSystem; }).files;

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

  # a file entry whose destination furnish owns instead of hjem.
  isFurnishManaged = entry: builtins.isAttrs entry && (entry.furnishManaged or false);

  # the furnish-owned file entries as their own root unit under the spec's own
  # claims, so a per-entry claim still drops one before it becomes a
  # declaration. the selector is stripped here.
  furnishUnit =
    spec:
    (builtins.intersectAttrs claimKeysAttrs spec)
    // {
      children = map (entry: entryUnit "files" (removeAttrs entry [ "furnishManaged" ])) (
        builtins.filter isFurnishManaged (spec.files or [ ])
      );
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

  # home-manager config for a resolved spec, package plus noctalia templates.
  hmConfig =
    # home-manager's extended lib (has lib.hm.dag for activation scripts).
    lib: spec: pkgs:
    lib.mkMerge [
      # install the package if one survived resolve
      (
        let
          pkg = spec.pkg or null;
        in
        lib.mkIf (pkg != null) {
          home.packages = [ (pkg pkgs) ];
        }
      )

      # write each noctalia template into ~/.config/noctalia/templates/
      (lib.mkMerge (
        map (t: {
          home.activation."noctalia-template-${t.name}" = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            mkdir -p $HOME/.config/noctalia/templates/${t.subdir or ""}
            cat > $HOME/.config/noctalia/templates/${t.subdir or ""}${t.name} << 'EOF'
            ${builtins.readFile t.templateFile}
            EOF
          '';
        }) (spec.templates or [ ])
      ))
    ];

  # hjem file links for a resolved spec.
  hjemFiles =
    spec: pkgs:
    let
      noctaliaConfig = spec.noctaliaConfig or { };
    in
    lib.mkMerge [
      # copy each file into its own store path (not a flake-source subpath) so gc
      # can't strand the link and switch can recreate it.
      (lib.mkMerge (
        map (f: {
          ${f.dest}.source = builtins.path {
            path = f.src;
            name = "skadi-" + baseNameOf f.dest;
          };
        }) (builtins.filter (f: !(isFurnishManaged f)) (spec.files or [ ]))
      ))

      # serialise noctaliaConfig to toml so noctalia merges it
      (lib.mkIf (noctaliaConfig != { }) {
        ".config/noctalia/${noctaliaConfig._fileName}.toml".source =
          (pkgs.formats.toml { }).generate "noctalia-${noctaliaConfig._fileName}.toml"
            (removeAttrs noctaliaConfig [ "_fileName" ]);
      })
    ];
in
spec:
let
  # home units are the whole spec as one root leaf, with the nixos slice apart.
  homeUnits = [ (specUnit spec) ];
  ownsFiles = builtins.any isFurnishManaged (spec.files or [ ]);
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

  hjem =
    {
      pkgs,
      host ? null,
      user ? null,
      ...
    }:
    let
      resolved = (resolve homeUnits) { inherit host user; };
    in
    {
      files = hjemFiles resolved pkgs;
    };
}
// lib.optionalAttrs (spec ? nixos || ownsFiles) {
  # host-only system slice, resolved at host scope with no user. emitted when
  # the aspect declares one or when furnish owns one of its file entries.
  nixos =
    {
      pkgs,
      config,
      host ? null,
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
      in
      {
        # a module that names a furnish option owns the import.
        imports = [
          ./furnish/runtime.nix
          {
            lexicon.furnish.declarations = furnishFiles.mkDeclarations {
              filesystemNamespace = "${system}/${hostName}";
              principals = hostPrincipals {
                inherit system;
                host = hostName;
              };
              files = resolved.files or [ ];
            };
          }
        ]
        ++ lib.optional (spec ? nixos) rawSlice;
      };
}
