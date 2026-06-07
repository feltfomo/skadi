{ lib }:
{
  pkg ? null,
  files ? [ ],
  templates ? [ ],
  imports ? [ ],
  noctaliaConfig ? { },
}:
{
  homeManager =
    { pkgs, lib, ... }:
    {
      inherit imports;

      config = lib.mkMerge [
        # install the package if one was given
        (lib.mkIf (pkg != null) {
          home.packages = [ (pkg pkgs) ];
        })

        # write each noctalia template into ~/.config/noctalia/templates/
        # runs as an activation script so it happens after the store is linked
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
    };

  hjem =
    { pkgs, ... }:
    {
      files = lib.mkMerge [
        # link static config files straight into home
        (lib.mkMerge (
          map (f: {
            ${f.dest}.source = f.src;
          }) files
        ))

        # serialise noctaliaConfig to toml and link it so noctalia merges it
        (lib.mkIf (noctaliaConfig != { }) {
          ".config/noctalia/${noctaliaConfig._fileName}.toml".source =
            (pkgs.formats.toml { }).generate "noctalia-${noctaliaConfig._fileName}.toml"
              (removeAttrs noctaliaConfig [ "_fileName" ]);
        })
      ];
    };
}
