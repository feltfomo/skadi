{ ... }:
{
  flake.modules.nixos.firefox =
    { pkgs, ... }:
    {
      home-manager.users.feltfomo =
        { lib, ... }:
        {
          home = {
            packages = with pkgs; [ firefox ];
            activation.firefox-theme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
              mkdir -p $HOME/.config/noctalia/templates/firefox
              cat > $HOME/.config/noctalia/templates/firefox/userChrome.css << 'EOF'
              ${builtins.readFile ../configs/firefox/chrome/userChrome.css}
              EOF
              cat > $HOME/.config/noctalia/templates/firefox/userContent.css << 'EOF'
              ${builtins.readFile ../configs/firefox/chrome/userContent.css}
              EOF
            '';
          };
        };
    };
}
