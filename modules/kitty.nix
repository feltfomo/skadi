{ ... }:
{
  flake.nixosModules.kitty =
    { ... }:
    {
      home-manager.users.feltfomo =
        { lib, ... }:
        {
          programs.kitty = {
            enable = true;
            enableGitIntegration = true;
            settings = {
              cusor_shape = "beam";
              cursor_trail = "1";
              include = "current-theme.conf";
            };
            extraConfig = "include themes/noctalia-extras.conf";
          };
          home.activation.noctalia-templates = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            mkdir -p $HOME/.config/noctalia/templates
            cat > $HOME/.config/noctalia/templates/kitty.conf << 'EOF'
            scrollbar_handle_color {{colors.primary.default.hex}}
            EOF
          '';
        };
    };
}
