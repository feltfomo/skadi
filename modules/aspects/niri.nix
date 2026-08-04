{
  inputs,
  program,
  rootPath,
  ...
}:
{
  den.aspects.niri = program {
    hosts = [
      "khion"
      "lumi"
    ];
    nixos = { pkgs, ... }: [
      {
        hosts = [
          "khion"
          "lumi"
        ];
        imports = [ inputs.niri.nixosModules.niri ];
        nixpkgs.overlays = [ inputs.niri.overlays.niri ];
        programs.niri = {
          enable = true;
          package = pkgs.niri-unstable;
        };
        environment.systemPackages = [ pkgs.xwayland-satellite-unstable ];
        services.flatpak.enable = true;
      }
    ];
    directories = [
      {
        src = "${rootPath}/configs/niri";
        dest = ".config/niri";
      }
    ];
    theme = {
      id = "niri";
      source = "${rootPath}/configs/niri/colors.kdl";
      output = ".config/niri/colors.kdl";
      renderers.dms = { };
    };
  };
}
