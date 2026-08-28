{ den, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      # fleet-aware nh wrappers: `nix run .#khion -- switch`, and equivalent
      # wrappers for every other host and standalone home Den exposes.
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
