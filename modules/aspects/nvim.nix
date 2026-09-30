{
  program,
  rootPath,
  ...
}:
{
  # lazy.nvim self-clones for now; swap to nix-supplied vimPlugins store
  # paths once the plugin list actually settles.
  den.aspects.nvim = program {
    pkg =
      pkgs:
      pkgs.symlinkJoin {
        name = "neovim-with-deps";
        paths = with pkgs; [
          gcc
          zls
          ols
          nixd
          cargo
          neovim
          ktlint
          pyright
          rustfmt
          tree-sitter
          wl-clipboard
          rust-analyzer
          google-java-format
          lua-language-server
          jdt-language-server
          kotlin-language-server
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
            "end4-pc"
            "serpantinum"
          ];
        };
        caelestia.source = "${rootPath}/configs/nvim/colors/theme-templates/caelestia-palette.lua";
      };
    };
  };
}
