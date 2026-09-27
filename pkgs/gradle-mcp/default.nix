{ pkgs }:
let
  jar = pkgs.fetchurl {
    url = "https://repo1.maven.org/maven2/dev/rnett/gradle-mcp/gradle-mcp/0.0.15/gradle-mcp-0.0.15.jar";
    hash = "sha256-b1yJDFmYvIq6f2G1y6mK5l2k3x0p4y7d4n8a1s3w5I=";
  };
in
pkgs.writeShellApplication {
  name = "gradle-mcp";
  runtimeInputs = [
    pkgs.jdk25
    pkgs.gradle
    pkgs.coreutils
  ];
  text = ''
    exec ${pkgs.jdk25}/bin/java \
      -jar ${jar} stdio "$@"
  '';
}
