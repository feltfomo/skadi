# the boot from grub to the greeter in the fallback palette: grub's menu, a quiet kernel, the
# plymouth splash with the disk password, and the console's colors. these stages run before the
# live palette exists, so they read the fixed one.
{ config, ... }:
let
  palette = config.skadi.fallbackPalette;
in
{
  skadi.packages.skadi-grub-theme = ./_grub-renderer.nix;

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
      published = "${home}/.local/state/skadi/boot.json";
      grubTheme = pkgs.callPackage ./_grub-theme.nix { inherit palette hostName resolution; };
      plymouthTheme = pkgs.callPackage ./_plymouth-theme.nix { inherit palette hostName; };
    in
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
        description = "The user whose live palette and wallpaper the boot menu follows.";
      };

      config = {
        boot.loader.grub = {
          theme = grubTheme;
          splashImage = "${grubTheme}/background.png";
          # install-grub replaces /theme on every switch, so the live theme has its own directory.
          extraConfig = ''
            if [ -f /skadi/theme.txt ]; then
              insmod jpeg
              set theme=/skadi/theme.txt
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

        # renders the publisher's palette and wallpaper onto the esp whenever their session publishes
        # a change. a render goes to a temporary directory first, so a failed one keeps the last
        # theme, and the stamp skips the render at boot when nothing changed.
        systemd.paths.skadi-boot-theme = lib.mkIf (publisher != null) {
          wantedBy = [ "multi-user.target" ];
          pathConfig.PathChanged = published;
        };
        systemd.services.skadi-boot-theme = lib.mkIf (publisher != null) {
          description = "Render the live boot menu onto the ESP";
          wantedBy = [ "multi-user.target" ];
          unitConfig.RequiresMountsFor = [
            "/boot"
            home
          ];
          path = with pkgs; [
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
                echo ${lib.getExe pkgs.skadi-grub-theme} ${hostName} ${toString resolution.width} ${toString resolution.height}
                cat ${published}
                if [ ''${#options[@]} -gt 0 ]; then stat --format '%s %Y' "$wallpaper"; fi
              } | sha256sum
            )
            if [ "$(cat /boot/skadi/stamp 2>/dev/null)" = "$stamp" ]; then exit 0; fi

            work=$(mktemp --directory)
            trap 'rm -rf "$work"' EXIT
            ${lib.getExe pkgs.skadi-grub-theme} --palette ${published} --host ${hostName} \
              --width ${toString resolution.width} --height ${toString resolution.height} \
              "''${options[@]}" "$work/theme"
            echo "$stamp" > "$work/theme/stamp"
            rm -rf /boot/skadi.new
            cp -r "$work/theme" /boot/skadi.new
            rm -rf /boot/skadi
            mv /boot/skadi.new /boot/skadi
          '';
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

        # standard ansi hues from the palette's semantic roles, since programs on a tty expect them.
        console.colors = map colors.bare (
          with palette;
          [
            surface
            error
            success
            warning
            primary
            tertiary
            primary
            on_surface
            outline_variant
            error
            success
            warning
            primary
            tertiary
            primary
            on_surface
          ]
        );

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
