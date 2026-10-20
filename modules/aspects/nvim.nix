{
  program,
  rootPath,
  ...
}:
{
  # lazy.nvim clones plugins until the plugin list is stable enough to pin in nix.
  den.aspects.nvim = program {
    pkg =
      pkgs:
      pkgs.symlinkJoin {
        name = "neovim-with-deps";
        paths = with pkgs; [
          kotlin-language-server
          lua-language-server
          jdt-language-server
          google-java-format
          rust-analyzer
          wl-clipboard
          tree-sitter
          pyright
          rustfmt
          neovim
          ktlint
          cargo
          nixd
          gcc
          zls
          ols
        ];
      };
    directories = [
      {
        src = "${rootPath}/configs/nvim";
        dest = ".config/nvim";
      }
    ];
    theme = {
      id = "nvim";
      output = ".config/nvim/lua/reactive/palette.lua";
      reload = ''nvim --headless -u NONE -l "$HOME/.config/nvim/reload-theme.lua"'';
      renderers = {
        noctalia = {
          source = "${rootPath}/configs/nvim/colors/theme-templates/noctalia-dms.lua";
          sharedWith = [ "dms" ];
        };
        illogical-impulse = {
          source = "${rootPath}/configs/nvim/colors/theme-templates/illogical-impulse-end4-pc.lua";
          sharedWith = [
            "serpantinum"
            "end4-pc"
          ];
        };
        caelestia.source = "${rootPath}/configs/nvim/colors/theme-templates/caelestia-palette.lua";
      };
    };
  };
}
