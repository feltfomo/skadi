{
  lexicon,
  rootPath,
  ...
}:
{
  # lazy.nvim clones plugins until the plugin list is stable enough to pin in nix.
  den.aspects.nvim = lexicon {
    package =
      pkgs:
      let
        kotlinLsp = pkgs.callPackage ../../pkgs/kotlin-lsp { };
        neoTree = pkgs.callPackage ../../pkgs/neo-tree { };
        javaDebug = pkgs.vscode-extensions.vscjava.vscode-java-debug;
      in
      pkgs.symlinkJoin {
        name = "neovim-with-deps";
        nativeBuildInputs = [ pkgs.makeWrapper ];
        paths = with pkgs; [
          vscode-extensions.vadimcn.vscode-lldb.adapter
          vscode-langservers-extracted
          yaml-language-server
          lua-language-server
          jdt-language-server
          google-java-format
          rust-analyzer
          wl-clipboard
          tree-sitter
          clang-tools
          kotlinLsp
          ripgrep
          lazygit
          pyright
          prettier
          nushell
          deadnix
          rustfmt
          stylua
          neovim
          ktlint
          nixfmt
          statix
          taplo
          ruff
          cargo
          nixd
          gcc
          zls
          ols
          fd
        ];
        postBuild = ''
          wrapProgram "$out/bin/nvim" \
            --set NVIM_NEO_TREE_DIR "${neoTree}" \
            --set KOTLIN_LSP_DIR "${kotlinLsp}/share/kotlin-lsp" \
            --set NVIM_JAVA_DEBUG_DIR "${javaDebug}/share/vscode/extensions/vscjava.vscode-java-debug/server"
        '';
      };
    furnish.directories = [
      {
        source = "${rootPath}/configs/nvim";
        destination = ".config/nvim";
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
