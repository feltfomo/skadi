# the boot from grub to the greeter: grub's menu, a quiet kernel, the plymouth splash with the disk
# password, and the console's colors. each stage is built in the fallback palette. when a user
# publishes their live palette (live.nix), a service renders the live versions onto the esp, which
# boot reads before the root filesystem is unlocked, and each stage prefers those when present.
{ config, ... }:
let
  palette = config.skadi.fallbackPalette;
in
{
  skadi.packages.skadi-boot-theme = ./_renderer.nix;

  # declared on every host, since a host sets its resolution and the publisher's user aspect
  # sets the publisher whether or not the host includes boot-theme. without boot-theme they do
  # nothing.
  den.default.nixos =
    { lib, ... }:
    {
      # the screen's native mode, which grub asks the firmware for first.
      options.skadi.bootTheme.resolution = {
        width = lib.mkOption {
          type = lib.types.ints.positive;
          default = 1920;
        };
        height = lib.mkOption {
          type = lib.types.ints.positive;
          default = 1080;
        };
      };

      # set by the boot-theme-live user aspect, so two users can't both claim the esp.
      options.skadi.bootTheme.publisher = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "The user whose live palette and wallpaper the boot theme follows.";
      };
    };

  den.aspects.boot-theme.nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      colors = import ./_colors.nix { inherit lib; };
      inherit (config.networking) hostName;
      inherit (config.skadi.bootTheme) resolution;
      gfxmode = lib.concatStringsSep "," (
        lib.unique [
          "${toString resolution.width}x${toString resolution.height}"
          "1920x1080"
          "auto"
        ]
      );
      inherit (config.skadi.bootTheme) publisher;
      home = config.users.users.${publisher}.home;
      # the console's sixteen colors in ansi order, which programs on a tty expect: black, red,
      # green, yellow, blue, magenta, cyan, white, then the bright set.
      consoleRoles = [
        "surface"
        "error"
        "success"
        "warning"
        "primary"
        "tertiary"
        "primary"
        "on_surface"
        "outline_variant"
        "error"
        "success"
        "warning"
        "primary"
        "tertiary"
        "primary"
        "on_surface"
      ];
      published = "${home}/.local/state/skadi/boot.json";
      fallback = pkgs.callPackage ./_fallback-theme.nix { inherit palette hostName resolution; };
      plymouthTheme = pkgs.callPackage ./_plymouth-theme.nix { inherit palette fallback; };
    in
    {
      config = {
        boot.loader.grub = {
          theme = "${fallback}/grub";
          splashImage = "${fallback}/grub/backdrop.png";
          # install-grub replaces /theme on every switch, so the live theme has its own directory. a
          # video wallpaper renders the live theme without a photo, as pngs.
          extraConfig = ''
            if [ -f /skadi/grub/theme.txt ]; then
              insmod jpeg
              if [ -f /skadi/grub/backdrop.jpg ]; then
                background_image /skadi/grub/backdrop.jpg
              else
                background_image /skadi/grub/backdrop.png
              fi
              set theme=/skadi/grub/theme.txt
              export theme
            fi
          '';
          # firmware without the native mode falls back to 1080p, where the text and rows look larger.
          gfxmodeEfi = gfxmode;
          gfxmodeBios = gfxmode;
        };

        boot.plymouth = {
          enable = true;
          theme = "skadi";
          themePackages = [ plymouthTheme ];
          # the initrd's fontconfig knows only this file, so every family name resolves to it.
          font = "${pkgs.maple-mono.NF}/share/fonts/truetype/MapleMono-NF-Regular.ttf";
        };

        # the splash reads the live images from the esp, which isn't encrypted, so the initrd mounts
        # it read-only before plymouth starts. the disk shows up with the password's partition, so the
        # splash waits on it only briefly, and a missing esp gives up quickly and keeps the fallback.
        # it's unmounted before the switch to the real root, which mounts the same esp read-write.
        boot.initrd.supportedFilesystems = lib.mkIf (publisher != null) [ "vfat" ];
        boot.initrd.systemd.mounts = lib.mkIf (publisher != null) [
          {
            what = config.fileSystems."/boot".device;
            where = "/run/skadi-esp";
            type = "vfat";
            options = "ro";
            wantedBy = [ "plymouth-start.service" ];
            conflicts = [ "initrd-switch-root.target" ];
            before = [
              "initrd-switch-root.target"
              "plymouth-start.service"
            ];
            unitConfig.JobTimeoutSec = 5;
          }
        ];

        # renders the publisher's palette and wallpaper onto the esp at boot, on a switch that changes
        # the renderer, and whenever their session publishes a change. a render goes to a temporary
        # directory first, so a failed one keeps the last theme, and the stamp skips the render when
        # nothing changed.
        #
        # the service stays active after it renders, so a switch restarts it when it changes. that
        # also means starting it again does nothing, so the path unit restarts it instead.
        systemd.paths.skadi-boot-theme = lib.mkIf (publisher != null) {
          wantedBy = [ "multi-user.target" ];
          pathConfig = {
            Unit = "skadi-boot-theme-refresh.service";
            PathChanged = published;
          };
        };
        systemd.services.skadi-boot-theme-refresh = lib.mkIf (publisher != null) {
          description = "Re-render the live boot theme after a published change";
          serviceConfig = {
            ExecStart = "${config.systemd.package}/bin/systemctl restart skadi-boot-theme.service";
            Type = "oneshot";
          };
        };
        systemd.services.skadi-boot-theme = lib.mkIf (publisher != null) {
          description = "Render the live boot theme onto the ESP";
          wantedBy = [ "multi-user.target" ];
          serviceConfig.RemainAfterExit = true;
          unitConfig.RequiresMountsFor = [
            "/boot"
            home
          ];
          path = with pkgs; [
            config.systemd.package
            coreutils
            gnugrep
            file
            jq
          ];
          serviceConfig.Type = "oneshot";
          script = ''
            [ -f ${published} ] || exit 0
            wallpaper=$(jq -r '.wallpaper // ""' ${published})
            # a video wallpaper keeps the flat surface.
            options=()
            if [ -f "$wallpaper" ] && file --brief --mime-type "$wallpaper" | grep -q '^image/'; then
              options=(--wallpaper "$wallpaper")
            fi
            stamp=$(
              {
                echo ${lib.getExe pkgs.skadi-boot-theme} ${hostName} ${toString resolution.width} ${toString resolution.height}
                echo ${toString consoleRoles}
                cat ${published}
                if [ ''${#options[@]} -gt 0 ]; then stat --format '%s %Y' "$wallpaper"; fi
              } | sha256sum
            )
            if [ "$(cat /boot/skadi/stamp 2>/dev/null)" = "$stamp" ]; then exit 0; fi

            work=$(mktemp --directory)
            trap 'rm -rf "$work"' EXIT
            ${lib.getExe pkgs.skadi-boot-theme} --palette ${published} --host ${hostName} \
              --width ${toString resolution.width} --height ${toString resolution.height} \
              "''${options[@]}" "$work/theme"

            # setvtrgb's format: one line each for red, green and blue, sixteen decimals apiece.
            for channel in 1 3 5; do
              values=()
              for role in ${toString consoleRoles}; do
                hex=$(jq -r --arg role "$role" '.[$role]' ${published})
                values+=("$((16#''${hex:channel:2}))")
              done
              (IFS=,; echo "''${values[*]}")
            done > "$work/theme/vtrgb"

            echo "$stamp" > "$work/theme/stamp"
            rm -rf /boot/skadi.new
            cp -r "$work/theme" /boot/skadi.new
            rm -rf /boot/skadi
            mv /boot/skadi.new /boot/skadi
            systemctl start skadi-console-colors.service
          '';
        };

        # the kernel starts the console in the fallback palette, and this swaps in the live one. it
        # waits for plymouth to quit, since plymouth writes back the palette it found when it started.
        systemd.services.skadi-console-colors = lib.mkIf (publisher != null) {
          description = "Load the live palette into the console";
          wantedBy = [ "multi-user.target" ];
          after = [
            "plymouth-quit-wait.service"
            "plymouth-quit.service"
          ];
          unitConfig = {
            ConditionPathExists = "/boot/skadi/vtrgb";
            RequiresMountsFor = [ "/boot" ];
          };
          serviceConfig = {
            ExecStart = "${pkgs.kbd}/bin/setvtrgb /boot/skadi/vtrgb";
            Type = "oneshot";
          };
        };

        # errors still reach the journal; on screen they'd land on the password prompt.
        boot.consoleLogLevel = 3;
        # the console takes the screen as soon as the driver loads. it waits for text otherwise, and
        # on a quiet boot the firmware's last frame, grub's menu, shows whenever nothing else draws.
        boot.kernelParams = [
          "rd.systemd.show_status=auto"
          "vt.global_cursor_default=0"
          "rd.udev.log_level=3"
          "fbcon=nodefer"
          "quiet"
        ];

        console.colors = map (role: colors.bare palette.${role}) consoleRoles;

        # bold terminus at about 45 rows. at 1440p the kernel picks the same size itself, but no bold.
        console = {
          font = if resolution.height >= 1440 then "ter-v32b" else "ter-v24b";
          packages = [ pkgs.terminus_font ];
          earlySetup = true;
        };

        # the splash quits once greetd starts. it can't wait for boot to settle, since boot waits for
        # the splash to quit. the console fills the gap in the palette's surface.
        services.greetd.greeterManagesPlymouth = lib.mkIf config.services.greetd.enable true;
        systemd.services.plymouth-quit = lib.mkIf config.services.greetd.enable {
          after = [ "greetd.service" ];
          serviceConfig.ExecStart = [
            ""
            "-${config.boot.plymouth.package}/bin/plymouth quit --retain-splash"
          ];
        };
      };
    };
}
