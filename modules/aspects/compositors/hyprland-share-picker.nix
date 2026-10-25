{
  den,
  lexicon,
  rootPath,
  ...
}:
{
  den.aspects.hyprland.includes = [
    den.aspects.hyprland-share-picker
    den.aspects.gtk-theme
  ];

  den.aspects.hyprland-share-picker = lexicon {
    nixos = { pkgs, ... }: [
      {
        value.environment.systemPackages = [ pkgs.hyprland-preview-share-picker ];
      }
    ];

    furnish.files = { pkgs, ... }: [
      {
        destination = ".config/hypr/xdph.conf";
        source = pkgs.writeText "hyprland-share-picker-portal.conf" ''
          screencopy {
            custom_picker_binary = ${pkgs.lib.getExe pkgs.hyprland-preview-share-picker}
          }
        '';
      }
      {
        destination = ".config/hyprland-preview-share-picker/config.yaml";
        source = (pkgs.formats.yaml { }).generate "hyprland-share-picker.yaml" {
          stylesheets = [ "style.css" ];
          default_page = "windows";
          window = {
            width = 1080;
            height = 640;
          };
          image = {
            resize_size = 480;
            widget_size = 160;
          };
          classes.window = "share-picker";
          windows = {
            min_per_row = 2;
            max_per_row = 3;
            spacing = 16;
            clicks = 2;
          };
          outputs = {
            show_label = true;
            spacing = 8;
            clicks = 2;
          };
          region.command = "${pkgs.lib.getExe pkgs.slurp} -f '%o@%X,%Y,%W,%H'";
        };
      }
      {
        destination = ".config/hyprland-preview-share-picker/style.css";
        source = "${rootPath}/configs/hyprland-share-picker/style.css";
      }
    ];
  };
}
