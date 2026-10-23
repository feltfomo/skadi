{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      checks = inputs.nixpkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
        nvim-tasks = pkgs.runCommand "nvim-tasks-check" { nativeBuildInputs = [ pkgs.neovim ]; } ''
          set -euo pipefail
          export XDG_STATE_HOME="$TMPDIR/state"
          export XDG_CACHE_HOME="$TMPDIR/cache"
          export XDG_DATA_HOME="$TMPDIR/data"
          nvim --headless -u NONE -l ${../../tests/nvim-tasks.lua} \
            ${../..} "$TMPDIR/devenv-fixture"
          nvim --headless -u NONE -l ${../../tests/nvim-ide.lua} \
            ${../..} "$TMPDIR/ide-fixture"
          nvim --headless -u NONE -l ${../../tests/nvim-tasks-ui.lua} \
            ${../..} "$TMPDIR/picker-fixture" \
            ${pkgs.vimPlugins.telescope-nvim} ${pkgs.vimPlugins.plenary-nvim}
          touch "$out"
        '';
      };
    };
}
