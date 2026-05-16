{
  lib,
  ...
}:
{
  options.flake.factory = lib.mkOption {
    type = lib.types.attrsOf lib.types.unspecified;
    default = { };
  };

  config.flake.factory.program =
    {
      pkg ? null,
      files ? [ ],
      templates ? [ ],
    }:
    { ... }:
    {
      home-manager.users.feltfomo =
        { lib, ... }:
        lib.mkMerge [
          (lib.mkIf (pkg != null) {
            home.packages = [ pkg ];
          })
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

      hjem.users.feltfomo.files = lib.mkMerge (
        map (f: {
          ${f.dest}.source = f.src;
        }) files
      );
    };
}
