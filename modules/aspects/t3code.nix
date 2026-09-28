{ inputs, ... }:
{
  flake-file.inputs.t3-code-nix.url = "github:LisaScheers/t3-code-nix";

  den.aspects.t3code.homeManager =
    { config, lib, ... }:
    {
      imports = [ inputs.t3-code-nix.homeModules.t3code ];

      programs.t3code.enable = true;
      services.t3code.enable = true;

      # The prebuilt AppImage's desktop entry is outside usr/share, so its wrapper omits it.
      xdg.desktopEntries.t3code = {
        name = "T3 Code";
        exec = "${lib.getExe config.programs.t3code.package} %U";
        icon = "${config.programs.t3code.package.extracted}/t3code.png";
        categories = [ "Development" ];
        mimeType = [
          "x-scheme-handler/t3code"
          "x-scheme-handler/t3code-dev"
        ];
        settings.StartupWMClass = "t3code";
      };
    };
}
