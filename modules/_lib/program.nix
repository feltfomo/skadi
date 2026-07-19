# _lib/program.nix -- lowers one aspect spec into NixOS / Home Manager / hjem
# class modules. ownership rides the spec (hosts/users/exceptHosts/exceptUsers/
# when) and resolves lazily; untagged specs stay global.
{
  lib,
  resolve,
  resolveSystem,
}:
let
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

  # home-manager config for a resolved spec: package + noctalia template scripts.
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
        }) (spec.files or [ ])
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
  # home units: the whole spec as one root leaf (the nixos slice stays separate).
  homeUnits = [ (specUnit spec) ];
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
// lib.optionalAttrs (spec ? nixos) {
  # host-only system slice: resolves at host scope (no user), only emitted when
  # the aspect declares one.
  nixos =
    {
      pkgs,
      config,
      host ? null,
      ...
    }:
    (resolveSystem (spec.nixos { inherit pkgs config; })) { inherit host; };
}
