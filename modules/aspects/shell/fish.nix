{
  den.aspects.fish.homeManager = { pkgs, ... }: {
    programs.fish = {
      enable = true;

      plugins = with pkgs.fishPlugins; [
        {
          name = "fzf-fish";
          inherit (fzf-fish) src;
        }
        {
          name = "autopair";
          inherit (autopair) src;
        }
        {
          name = "done";
          inherit (done) src;
        }
      ];

      interactiveShellInit = ''
        set -g fish_greeting
        if not set -q SKADI_FASTFETCH_SHOWN
          set -gx SKADI_FASTFETCH_SHOWN 1
          fastfetch
        end
      '';

      shellAliases = {
        ls = "eza --icons=always";
        ll = "eza --icons=always --long --git";
        la = "eza --icons=always --long --all --git";
        lt = "eza --icons=always --tree";
        ltn = "eza --icons=always --tree --long";
      };

      shellAbbrs = {
        g = "git";
        gs = "git status --short";
        gd = "git diff";
        gl = "git log --oneline --decorate --graph";
        nfc = "nix flake check -L";
        nfu = "nix flake update";
        nrt = "sudo nixos-rebuild test --flake /etc/skadi#(hostname)";
        nrs = "sudo nixos-rebuild switch --flake /etc/skadi#(hostname)";
      };
    };
  };
}
