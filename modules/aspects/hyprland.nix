{
  inputs,
  rootPath,
  scoped,
  program,
  ...
}:
let
  # keep audio-playing windows opaque while inactive.
  audioOpacityService =
    { pkgs, ... }:
    let
      hyprctlPkg = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
      # body in scripts/audio-opacity.sh; writeShellApplication adds the shebang + PATH.
      audio-opacity = pkgs.writeShellApplication {
        name = "audio-opacity";
        runtimeInputs = [
          hyprctlPkg
          pkgs.pulseaudio
          pkgs.jq
          pkgs.gawk
          pkgs.procps
          pkgs.coreutils
        ];
        text = builtins.readFile ../../scripts/audio-opacity.sh;
      };
    in
    {
      systemd.user.services.audio-opacity = {
        Unit = {
          Description = "Undim windows that are playing audio while inactive";
          After = [ "graphical-session.target" ];
          PartOf = [ "graphical-session.target" ];
        };
        Service = {
          ExecStart = "${audio-opacity}/bin/audio-opacity";
          Restart = "always";
          RestartSec = 2;
        };
      };
    };

  # compositor + portal. flatpak sits here because it needs the portal.
  hyprNixos =
    { pkgs, ... }:
    {
      programs.hyprland = {
        enable = true;
        package = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
        portalPackage =
          inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland;
      };
      services.flatpak.enable = true;
    };
in
{
  # nixos = compositor, homeManager = daemon, hjem = config files.
  # add `users = [ ... ];` to a file to give it to only those users.
  den.aspects.hyprland =
    { host, user }:
    # khion-only; off-host `for` collapses the aspect to {}. matches short-
    # circuits a null host to false, the same guard the old onKhion had.
    let
      for = scoped.for { inherit host user; };
    in
    for { hosts = [ "khion" ]; } (
      let
        base = program {
          inherit host user;
          imports = [ audioOpacityService ];
          files = [
            {
              dest = ".config/hypr/hyprland.lua";
              src = "${rootPath}/configs/hypr/hyprland.lua";
            }
            {
              dest = ".config/hypr/autostart.lua";
              src = "${rootPath}/configs/hypr/autostart.lua";
            }
            {
              dest = ".config/hypr/binds.lua";
              src = "${rootPath}/configs/hypr/binds.lua";
            }
            {
              dest = ".config/hypr/decoration.lua";
              src = "${rootPath}/configs/hypr/decoration.lua";
            }
            {
              dest = ".config/hypr/environment.lua";
              src = "${rootPath}/configs/hypr/environment.lua";
            }
            {
              dest = ".config/hypr/globals.lua";
              src = "${rootPath}/configs/hypr/globals.lua";
            }
            {
              dest = ".config/hypr/monitor.lua";
              src = "${rootPath}/configs/hypr/monitor.lua";
            }
            {
              dest = ".config/hypr/hl.meta.lua";
              src = "${rootPath}/configs/hypr/hl.meta.lua";
            }
            {
              dest = ".config/hypr/helpers/workspace.lua";
              src = "${rootPath}/configs/hypr/helpers/workspace.lua";
            }
          ];
          templates = [
            {
              name = "colors.lua";
              templateFile = "${rootPath}/configs/hypr/colors.lua";
              subdir = "hyprland/";
            }
          ];
          noctaliaConfig = {
            _fileName = "hyprland";
            theme.templates.user.hyprland = {
              input_path = "~/.config/noctalia/templates/hyprland/colors.lua";
              output_path = "~/.config/hypr/colors.lua";
            };
          };
        };
      in
      {
        nixos = hyprNixos;
        inherit (base) homeManager hjem;
      }
    );
}
