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
          pyright
          zls
          ols
          wl-clipboard
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
      renderers = {
        noctalia = {
          source = "${rootPath}/configs/nvim/colors/theme-templates/noctalia-dms.lua";
          output = ".config/nvim/lua/reactive/palette.lua";
          reload = "find \"$XDG_RUNTIME_DIR\" -maxdepth 1 -type s -name 'nvim.*.0' -exec nvim --server {} --remote-expr 'execute(\"colorscheme reactive\")' \\; >/dev/null";
        };
        dms = {
          source = "${rootPath}/configs/nvim/colors/theme-templates/noctalia-dms.lua";
          output = ".config/nvim/lua/reactive/palette.lua";
          reload = "find \"$XDG_RUNTIME_DIR\" -maxdepth 1 -type s -name 'nvim.*.0' -exec nvim --server {} --remote-expr 'execute(\"colorscheme reactive\")' \\; >/dev/null";
        };
        illogical-impulse = {
          source = "${rootPath}/configs/nvim/colors/theme-templates/illogical-impulse-end4-pc.lua";
          output = ".config/nvim/lua/reactive/palette.lua";
          reload = "find \"$XDG_RUNTIME_DIR\" -maxdepth 1 -type s -name 'nvim.*.0' -exec nvim --server {} --remote-expr 'execute(\"colorscheme reactive\")' \\; >/dev/null";
        };
        end4-pc = {
          source = "${rootPath}/configs/nvim/colors/theme-templates/illogical-impulse-end4-pc.lua";
          output = ".config/nvim/lua/reactive/palette.lua";
          reload = "find \"$XDG_RUNTIME_DIR\" -maxdepth 1 -type s -name 'nvim.*.0' -exec nvim --server {} --remote-expr 'execute(\"colorscheme reactive\")' \\; >/dev/null";
        };
        caelestia = {
          source = "${rootPath}/configs/nvim/colors/theme-templates/caelestia-palette.lua";
          output = ".config/nvim/lua/reactive/palette.lua";
          placedAs = "palette.lua";
          reload = "find \"$XDG_RUNTIME_DIR\" -maxdepth 1 -type s -name 'nvim.*.0' -exec nvim --server {} --remote-expr 'execute(\"colorscheme reactive\")' \\; >/dev/null";
        };
      };
    };
  };
}
