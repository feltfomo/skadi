{
  inputs,
  lib,
  ...
}:
{
  options.flake.factory = lib.mkOption {
    type = lib.types.attrsOf lib.types.unspecified;
    default = { };
  };
  config = {
    flake.factory = {
      terminal =
        {
          name,
          pkg,
          configPath,
          templateFile,
        }:
        { ... }:
        {
          imports = [ inputs.self.nixos.modules.terminalPackages ];
          hjem.users.feltfomo.files.".config/${name}/${name}.conf".source = configPath + "/${name}.conf";
          home-manager.users.feltfomo =
            { lib, ... }:
            {
              home = {
                packages = [ pkg ];
                activation."noctalia-template-${name}" = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
                  mkdir -p $HOME/.config/noctalia/templates
                  cat > $HOME/.config/noctalia/templates/${name}.conf << 'EOF'
                  ${builtins.readFile templateFile}
                  EOF
                '';
              };
            };
        };
    };
  };
}
