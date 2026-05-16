{ ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      devShells.default = pkgs.mkShell {
        packages = with pkgs; [
          nixd
          alejandra
          nix-tree
          nvd
          statix
          deadnix
          lua
          lua-language-server
          stylua
          vscode-langservers-extracted
          prettierd
        ];
      };
    };
}
