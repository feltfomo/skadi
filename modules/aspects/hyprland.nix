{
  inputs,
  lib,
  rootPath,
  ...
}:
let
  program = import ../_lib/program.nix { inherit lib; };

  # Event-driven watcher: keeps any window that is playing audio (Spotify, a
  # browser tab, etc.) fully opaque so it does not dim while it is inactive.
  audioOpacityService =
    { pkgs, lib, ... }:
    let
      hyprctlPkg = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
      audio-opacity = pkgs.writeShellScriptBin "audio-opacity" ''
        export PATH=${lib.makeBinPath [ hyprctlPkg pkgs.pulseaudio pkgs.jq pkgs.gawk pkgs.procps pkgs.coreutils ]}:$PATH

        # Reach the running Hyprland even if systemd did not inherit its signature.
        if [ -z "$HYPRLAND_INSTANCE_SIGNATURE" ] && [ -d "$XDG_RUNTIME_DIR/hypr" ]; then
          HYPRLAND_INSTANCE_SIGNATURE=$(ls -t "$XDG_RUNTIME_DIR/hypr" | head -n1)
          export HYPRLAND_INSTANCE_SIGNATURE
        fi

        reconcile() {
          # PIDs of streams that are actually playing (not corked / paused).
          playing=$(pactl -f json list sink-inputs 2>/dev/null \
            | jq -r '.[] | select(.corked==false) | .properties["application.process.id"] // empty')

          # Expand each to its full parent chain, so a browser's sandboxed audio
          # subprocess maps back to the main, window-owning process.
          ancestors=" "
          for pid in $playing; do
            cur=$pid
            n=0
            while [ -n "$cur" ] && [ "$cur" != "0" ] && [ "$cur" != "1" ] && [ "$n" -lt 32 ]; do
              ancestors="$ancestors$cur "
              cur=$(awk '/^PPid:/{print $2}' /proc/$cur/status 2>/dev/null)
              n=$((n + 1))
            done
          done

          # opaque ON for any window whose PID is in that set, OFF for the rest.
          hyprctl clients -j 2>/dev/null | jq -r '.[] | "\(.address) \(.pid)"' \
            | while read -r addr cpid; do
                [ -n "$addr" ] || continue
                case "$ancestors" in
                  *" $cpid "*) val=1 ;;
                  *) val=0 ;;
                esac
                hyprctl dispatch "hl.dsp.window.set_prop({ window = \"address:$addr\", prop = \"opaque\", value = \"$val\" })" >/dev/null 2>&1
              done
        }

        reconcile
        pactl subscribe 2>/dev/null | while read -r event; do
          case "$event" in
            *sink-input*) reconcile ;;
          esac
        done
      '';
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

  base = program {
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
  den.aspects.hyprland = base // {
    nixos =
      { pkgs, ... }:
      {
        programs.hyprland = {
          enable = true;
          package = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
          portalPackage =
            inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland;
        };

        # flatpak lives with the desktop that provides its xdg portal, not in
        # base. programs.hyprland already enables xdg.portal (+ the hyprland
        # backend), so flatpak's only hard dependency is satisfied right here.
        # a lean base install (generic/owner) has no desktop -> no app-store.
        services.flatpak.enable = true;
      };
  };
}