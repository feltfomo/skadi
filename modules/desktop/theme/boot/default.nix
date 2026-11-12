# the boot from grub to the greeter in the fallback palette: grub's menu, a quiet kernel, the
# plymouth splash with the disk password, and the console's colors. these stages run before the
# live palette exists, so they read the fixed one.
{ config, ... }:
let
  palette = config.skadi.fallbackPalette;
in
{
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

      config = {
        boot.loader.grub = {
          theme = grubTheme;
          splashImage = "${grubTheme}/background.png";
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

        # errors still reach the journal; on screen they'd land on the password prompt.
        boot.consoleLogLevel = 3;
        boot.kernelParams = [
          "rd.systemd.show_status=auto"
          "rd.udev.log_level=3"
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

        # plymouth keeps its last frame until the greeter's compositor draws over it, so there's no
        # black console between them.
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
