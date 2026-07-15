{
  program,
  rootPath,
  ...
}:
{
  # no hosts/users claim -- globally owned like kitty, resolved on whichever
  # user includes it. plugin bootstrap starts self-managed (lazy.nvim clones
  # itself); swap to nix-supplied vimPlugins store paths once the real plugin
  # list is settled, same as kitty's static file + noctalia template split.
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