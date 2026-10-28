{
  den.aspects.lua-development.homeManager = { pkgs, ... }: {
    home.packages = with pkgs; [
      lua-language-server
      stylua
    ];
  };
}
