{
  pkgs ? <nixpkgs> { },
}:
pkgs.mkShell {
  nativeBuildInputs = with pkgs.buildPackages; [ ruby_3_1 ];
}
