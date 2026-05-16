{ ... }:
{
  flake.modules.nixos.noctalia-templates =
    { pkgs, ... }:
    {
      hjem.users.feltfomo.files = {
        ".config/noctalia/user-templates.toml".source =
          (pkgs.formats.toml { }).generate "user-templates.toml"
            {
              config = { };
              templates.kitty = {
                input_path = "~/.config/noctalia/templates/kitty.conf";
                output_path = "~/.config/kitty/themes/skadi.conf";
                post_hook = "pkill -SIGUSR1 kitty";
              };
              templates.firefox-chrome = {
                input_path = "~/.config/noctalia/templates/firefox/userChrome.css";
                output_path = "~/.config/mozilla/firefox/449sgxzm.default/chrome/userChrome.css";
                post_hook = "pkill -HUP firefox";
              };
              templates.firefox-content = {
                input_path = "~/.config/noctalia/templates/firefox/userContent.css";
                output_path = "~/.config/mozilla/firefox/449sgxzm.default/chrome/userContent.css";
                post_hook = "pkill -HUP firefox";
              };
            };
      };
    };
}
