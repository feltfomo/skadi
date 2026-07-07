{ lib }:
let
  scoped = import ./scoped.nix { inherit lib; };

  # home-manager CONFIG for a spec fragment: package install + noctalia template
  # activation scripts. Returns a plain config attrset so fragments merge cleanly.
  hmConfig =
    # home-manager's extended lib (provides lib.hm.dag for activation scripts); a
    # superset of the file-level nixpkgs lib, so mkMerge / mkIf still resolve.
    lib:
    {
      pkg ? null,
      templates ? [ ],
      ...
    }:
    pkgs:
    lib.mkMerge [
      # install the package if one was given
      (lib.mkIf (pkg != null) {
        home.packages = [ (pkg pkgs) ];
      })

      # write each noctalia template into ~/.config/noctalia/templates/
      (lib.mkMerge (
        map (t: {
          home.activation."noctalia-template-${t.name}" = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            mkdir -p $HOME/.config/noctalia/templates/${t.subdir or ""}
            cat > $HOME/.config/noctalia/templates/${t.subdir or ""}${t.name} << 'EOF'
            ${builtins.readFile t.templateFile}
            EOF
          '';
        }) templates
      ))
    ];

  # hjem file links for a spec fragment. Each file entry may carry an optional
  # `users` / `hosts` list -- the register for who gets that file. Omit them and
  # the file links for everyone the aspect resolves for; set them and the file
  # self-selects via scoped.matches against `ctx` (the { host, user } den resolved
  # for this home). One line per file, no duplication.
  hjemFiles =
    ctx:
    {
      files ? [ ],
      noctaliaConfig ? { },
      ...
    }:
    pkgs:
    lib.mkMerge [
      # link static config files straight into home, filtered per entry
      (lib.mkMerge (
        map (
          f:
          lib.mkIf
            (scoped.matches {
              hosts = f.hosts or null;
              users = f.users or null;
            } ctx)
            {
              ${f.dest}.source = f.src;
            }
        ) files
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
  # { host, user } is the den context the aspect resolved for. Slices close over
  # it so per-file `users` / `hosts` tags can select without any extra wiring.
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
  spec = {
    inherit
      pkg
      files
      templates
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
      inherit imports;
      config = hmConfig lib spec pkgs;
    };

  hjem =
    {
      pkgs,
      ...
    }:
    {
      files = hjemFiles ctx spec pkgs;
    };
}
