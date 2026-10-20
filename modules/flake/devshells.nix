{ den, ... }:
{
  perSystem =
    { pkgs, self', ... }:
    {
      # fleet-aware nh wrappers cover every host and standalone home den exposes.
      packages = den.lib.nh.denPackages { fromFlake = true; } pkgs;

      devShells.default = pkgs.mkShell {
        packages = with pkgs; [
          vscode-langservers-extracted
          self'.packages.praxis
          yaml-language-server
          lua-language-server
          bashInteractive
          shellcheck
          marksman
          deadnix
          nixfmt
          statix
          stylua
          shfmt
          taplo
          nixd
        ];
      };
    };
}
