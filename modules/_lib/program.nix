{ lib, scoped }:
let
  # home-manager CONFIG for a resolved spec: package install + noctalia template
  # activation scripts. spec is already filtered by scoped.resolve, so pkg is
  # absent when narrowed out and templates are pre-selected.
  hmConfig =
    # home-manager's extended lib (provides lib.hm.dag for activation scripts); a
    # superset of the file-level nixpkgs lib, so mkMerge / mkIf still resolve.
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
        }) spec.templates
      ))
    ];

  # hjem file links for a resolved spec. scoped.resolve already dropped files
  # whose users/hosts miss and stripped those keys off survivors, so each entry
  # is just { dest; src; }. noctaliaConfig is absent when narrowed out.
  hjemFiles =
    spec: pkgs:
    let
      noctaliaConfig = spec.noctaliaConfig or { };
    in
    lib.mkMerge [
      # link static config files straight into home
      (lib.mkMerge (
        map (f: {
          ${f.dest}.source = f.src;
        }) spec.files
      ))

      # serialise noctaliaConfig to toml and link it so noctalia merges it
      (lib.mkIf (noctaliaConfig != { }) {
        ".config/noctalia/${noctaliaConfig._fileName}.toml".source =
          (pkgs.formats.toml { }).generate "noctalia-${noctaliaConfig._fileName}.toml"
            (removeAttrs noctaliaConfig [ "_fileName" ]);
      })
    ];
in
{
  # { host, user } is the den context the aspect resolved for. scoped.resolve
  # filters every field against it up front -- per-entry users/hosts on files and
  # templates, for-gated pkg/noctaliaConfig -- so the slices just consume what
  # survived. imports pass through untouched (no per-import selector yet).
  host ? null,
  user ? null,
  pkg ? null,
  files ? [ ],
  templates ? [ ],
  imports ? [ ],
  noctaliaConfig ? { },
}:
let
  ctx = { inherit host user; };
  resolved = scoped.resolve ctx {
    inherit
      pkg
      files
      templates
      imports
      noctaliaConfig
      ;
  };
in
{
  homeManager =
    {
      pkgs,
      lib,
      ...
    }:
    {
      inherit (resolved) imports;
      config = hmConfig lib resolved pkgs;
    };

  hjem =
    {
      pkgs,
      ...
    }:
    {
      files = hjemFiles resolved pkgs;
    };
}
