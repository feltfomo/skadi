{ pkgs }:
let
  python = pkgs.python3.withPackages (packages: [ packages.tomlkit ]);
in
pkgs.writeShellApplication {
  name = "app-theme-setup";
  text = ''
    exec ${python}/bin/python ${./app-theme-setup.py} "$@"
  '';
}
