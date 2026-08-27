{
  perSystem =
    { pkgs, ... }:
    {
      devShells.default = pkgs.mkShell {
        packages = with pkgs; [
          bashInteractive
          deadnix
          marksman
          nixd
          nixfmt
          shellcheck
          shfmt
          statix
          stylua
          taplo
          lua-language-server
          yaml-language-server
          vscode-langservers-extracted
        ];
      };
    };
}
