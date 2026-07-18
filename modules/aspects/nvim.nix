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
          neovim
          gcc
          tree-sitter
          nixd
          lua-language-server
          rust-analyzer
          jdt-language-server
          kotlin-language-server
          metals
          pyright
          zls
          ols
          wl-clipboard
        ];
      };
    files = [
      {
        dest = ".config/nvim/init.lua";
        src = "${rootPath}/configs/nvim/init.lua";
      }
      {
        dest = ".config/nvim/lua/config/lazy.lua";
        src = "${rootPath}/configs/nvim/lua/config/lazy.lua";
      }
      {
        dest = ".config/nvim/lua/plugins/lualine.lua";
        src = "${rootPath}/configs/nvim/lua/plugins/lualine.lua";
      }
      {
        dest = ".config/nvim/lua/plugins/telescope.lua";
        src = "${rootPath}/configs/nvim/lua/plugins/telescope.lua";
      }
      {
        dest = ".config/nvim/lua/plugins/treesitter.lua";
        src = "${rootPath}/configs/nvim/lua/plugins/treesitter.lua";
      }
      {
        dest = ".config/nvim/lua/plugins/lsp.lua";
        src = "${rootPath}/configs/nvim/lua/plugins/lsp.lua";
      }
      {
        dest = ".config/nvim/lua/plugins/metals.lua";
        src = "${rootPath}/configs/nvim/lua/plugins/metals.lua";
      }
    ];
  };
}
