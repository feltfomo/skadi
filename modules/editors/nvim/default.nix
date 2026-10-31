{
  lexicon,
  den,
  ...
}:
{
  # lazy.nvim clones plugins until the plugin list is stable enough to pin in nix.
  den.aspects.nvim = {
    includes = [ den.aspects.devenv ];
  }
  // lexicon {
    package =
      pkgs:
      let
        neoTree = pkgs.callPackage ./_neo-tree { };
      in
      pkgs.symlinkJoin {
        name = "neovim-with-deps";
        nativeBuildInputs = [ pkgs.makeWrapper ];
        paths = with pkgs; [
          wl-clipboard
          tree-sitter
          ripgrep
          lazygit
          neovim
          fd
        ];
        postBuild = ''
          wrapProgram "$out/bin/nvim" \
            --set NVIM_NEO_TREE_DIR "${neoTree}"
        '';
      };
    furnish.directories = [
      {
        source = ./config;
        destination = ".config/nvim";
      }
    ];
    theme = {
      id = "nvim";
      output = ".config/nvim/lua/reactive/palette.lua";
      reload = ''nvim --headless -u NONE -l "$HOME/.config/nvim/reload-theme.lua"'';
      template = ./config/colors/theme-templates/palette.lua;
    };
  };
}
