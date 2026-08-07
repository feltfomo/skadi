{
  den.aspects.fish.homeManager = _: {
    programs.fish = {
      enable = true;

      interactiveShellInit = ''
        set -g fish_greeting
        fastfetch
      '';

      shellAliases = {
        ls = "eza --icons=always";
        ln = "eza --icons=always --long";
        lt = "eza --icons=always --tree";
        ltn = "eza --icons=always --tree --long";
      };
    };
  };
}
