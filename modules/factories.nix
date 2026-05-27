{
  lib,
  inputs,
  rootPath,
  ...
}:
{
  # register the factory namespace so aspects can access flake.factory.*
  options.flake.factory = lib.mkOption {
    type = lib.types.attrsOf lib.types.unspecified;
    default = { };
  };

  # program factory — call this from any aspect to wire up a program's
  # package, config files, noctalia templates, and noctalia toml config
  config.flake.factory.program =
    {
      pkg ? null,
      files ? [ ],
      templates ? [ ],
      imports ? [ ],
      noctaliaConfig ? { },
    }:
    { pkgs, ... }:
    {
      imports = imports;

      home-manager.users.feltfomo =
        { lib, ... }:
        lib.mkMerge [
          # install the package if one was given
          (lib.mkIf (pkg != null) {
            home.packages = [ pkg ];
          })

          # write each noctalia template file into ~/.config/noctalia/templates/
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

      hjem.users.feltfomo.files = lib.mkMerge [
        # link static config files straight into home
        (lib.mkMerge (
          map (f: {
            ${f.dest}.source = f.src;
          }) files
        ))

        # if noctaliaConfig was given, serialise it to toml and link it into
        # ~/.config/noctalia/ so noctalia picks it up and merges it automatically
        (lib.mkIf (noctaliaConfig != { }) {
          ".config/noctalia/${noctaliaConfig._fileName}.toml".source =
            (pkgs.formats.toml { }).generate "noctalia-${noctaliaConfig._fileName}.toml"
              (removeAttrs noctaliaConfig [ "_fileName" ]);
        })
      ];
    };

  # hostModules factory — eliminates duplicate module loader files per host
  config.flake.factory.hostModules = host: {
    imports = (lib.filesystem.listFilesRecursive "${rootPath}/modules/_host-modules/${host}") ++ [
      inputs.self.modules.nixos.shared
    ];
  };
}
