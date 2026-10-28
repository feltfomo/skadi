{
  den.aspects.jvm-development.homeManager =
    { pkgs, ... }:
    let
      kotlinLsp = pkgs.callPackage ./_kotlin-lsp.nix { };
    in
    {
      home.packages = [
        pkgs.jdt-language-server
        kotlinLsp
      ];

      home.sessionVariables = {
        KOTLIN_LSP_DIR = "${kotlinLsp}/share/kotlin-lsp";
        NVIM_JAVA_DEBUG_DIR = "${pkgs.vscode-extensions.vscjava.vscode-java-debug}/share/vscode/extensions/vscjava.vscode-java-debug/server";
      };
    };
}
