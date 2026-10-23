{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      checks = inputs.nixpkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
        nvim-tree = pkgs.runCommand "nvim-tree-check" { nativeBuildInputs = [ pkgs.neovim ]; } ''
          set -euo pipefail
          export XDG_STATE_HOME="$TMPDIR/state"
          export XDG_CACHE_HOME="$TMPDIR/cache"
          export XDG_DATA_HOME="$TMPDIR/data"
          nvim --headless -u NONE -i NONE -l ${../../tests/nvim-tree.lua} \
            ${../..} "$TMPDIR/tree-fixture" \
            ${pkgs.callPackage ../../pkgs/neo-tree { }} \
            ${pkgs.vimPlugins.nui-nvim} ${pkgs.vimPlugins.plenary-nvim}
          nvim --headless -u NONE -i NONE -l ${../../tests/nvim-tree-lazy.lua} \
            ${../..} "$TMPDIR/lazy-fixture" \
            ${pkgs.callPackage ../../pkgs/neo-tree { }} \
            ${pkgs.vimPlugins.nui-nvim} ${pkgs.vimPlugins.plenary-nvim} \
            ${pkgs.vimPlugins.mini-icons} ${pkgs.vimPlugins.lazy-nvim}
          touch "$out"
        '';
      };
    };
}
