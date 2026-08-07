{
  perSystem =
    { pkgs, ... }:
    {
      devShells.default = pkgs.mkShell {
        packages = with pkgs; [
          go
          nixd
          cargo
          gopls
          rustc
          taplo
          nixfmt
          statix
          stylua
          clippy
          rustfmt
          deadnix
          gofumpt
          marksman
          golangci-lint
          rust-analyzer
          lua-language-server
          yaml-language-server
          vscode-langservers-extracted
        ];
      };
    };
}
