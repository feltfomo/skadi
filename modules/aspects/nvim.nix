{
  program,
  rootPath,
  ...
}:
{
  # lazy.nvim self-clones for now; swap to nix-supplied vimPlugins store
  # paths once the plugin list actually settles.
  den.aspects.nvim = program {
    pkg = pkgs: pkgs.neovim;
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
    ];
  };
}
