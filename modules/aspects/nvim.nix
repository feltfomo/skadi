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
          ripgrep
          fd
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
      {
        dest = ".config/nvim/lsp/nixd.lua";
        src = "${rootPath}/configs/nvim/lsp/nixd.lua";
      }
      {
        dest = ".config/nvim/lsp/lua_ls.lua";
        src = "${rootPath}/configs/nvim/lsp/lua_ls.lua";
      }
      {
        dest = ".config/nvim/lsp/rust_analyzer.lua";
        src = "${rootPath}/configs/nvim/lsp/rust_analyzer.lua";
      }
      {
        dest = ".config/nvim/lsp/jdtls.lua";
        src = "${rootPath}/configs/nvim/lsp/jdtls.lua";
      }
      {
        dest = ".config/nvim/lsp/kotlin_language_server.lua";
        src = "${rootPath}/configs/nvim/lsp/kotlin_language_server.lua";
      }
      {
        dest = ".config/nvim/lsp/pyright.lua";
        src = "${rootPath}/configs/nvim/lsp/pyright.lua";
      }
      {
        dest = ".config/nvim/lsp/zls.lua";
        src = "${rootPath}/configs/nvim/lsp/zls.lua";
      }
      {
        dest = ".config/nvim/lsp/ols.lua";
        src = "${rootPath}/configs/nvim/lsp/ols.lua";
      }
    ];
  };
}
