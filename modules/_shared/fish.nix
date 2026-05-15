{ ... }:
{
  home-manager.users.feltfomo = {

    # install fish for feltfomo
    programs.fish = {
      enable = true;

      # launch terminal with fastfetch
      interactiveShellInit = ''
        fastfetch
      '';

      # set shell aliases
      shellAliases = {
        ls = "eza --icons";
        ln = "eza --icons --long";
        lt = "eza --icons --tree";
        ltn = "eza --icons --tree -long";
      };
    };
  };
}
