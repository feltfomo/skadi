{ inputs, pkgs }:
{
  desktopCommander = pkgs.buildNpmPackage {
    pname = "desktop-commander";
    version = "0.2.47";
    src = inputs.desktop-commander;
    npmDeps = pkgs.importNpmLock { npmRoot = inputs.desktop-commander; };
    npmConfigHook = pkgs.importNpmLock.npmConfigHook;
    npmRebuildFlags = [ "--ignore-scripts" ];
    dontCheckForBrokenSymlinks = true;
    postConfigure = ''
      find -path "*@vscode/ripgrep" -type d \
        -execdir mkdir -p {}/bin \; \
        -execdir ln -sf ${pkgs.ripgrep}/bin/rg {}/bin/rg \;
    '';
  };
}
