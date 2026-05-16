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
      # writes a noctalia template file to ~/.config/noctalia/templates/
      # noctalia reads it and outputs a themed file on wallpaper change
      noctaliaTemplate =
        {
          name,
          templateFile,
          subdir ? "",
        }:
        { ... }:
        {
          home-manager.users.feltfomo =
            { lib, ... }:
            {
              home.activation."noctalia-template-${name}" = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
                mkdir -p $HOME/.config/noctalia/templates/${subdir}
                cat > $HOME/.config/noctalia/templates/${subdir}${name} << 'EOF'
                ${builtins.readFile templateFile}
                EOF
              '';
            };
        };

      # sets up a terminal emulator with:
      # - the package installed via home-manager
      # - config linked via hjem
      # - noctalia template written for theming
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
