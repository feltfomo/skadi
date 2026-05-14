{ ... }:
{
  flake.nixosModules.noctalia-templates =
    { pkgs, ... }:
    {
      hjem.users.feltfomo.files = {
        ".config/noctalia/user-templates.toml".source =
          (pkgs.formats.toml { }).generate "user-templates.toml"
            {
              config = { };
              templates.kitty = {
                input_path = "~/.config/noctalia/templates/kitty.conf";
                output_path = "~/.config/kitty/themes/noctalia-extras.conf";
              };
            };
      };
    };
}
