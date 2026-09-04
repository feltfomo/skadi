{ den, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      # fleet-aware nh wrappers cover every host and standalone home den exposes.
      packages = den.lib.nh.denPackages { fromFlake = true; } pkgs;

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
