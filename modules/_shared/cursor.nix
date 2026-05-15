{ pkgs, ... }:
{
  home-manager.users.feltfomo = {
    # set cursor theme for gtk, x11/xwayland and wayland for feltfomo (got from wiki)
    home.pointerCursor =
      let
        getFrom = url: hash: name: {
          gtk.enable = true;
          x11.enable = true;
          name = name;
          size = 48;
          package = pkgs.runCommand "moveUp" { } ''
            mkdir -p $out/share/icons
            ln -s ${
              pkgs.fetchzip {
                url = url;
                hash = hash;
              }
            } $out/share/icons/${name}
          '';
        };
      in
      # get cursor theme from link
      getFrom "https://github.com/rose-pine/cursor/releases/download/v1.1.0/BreezeX-RosePine-Linux.tar.xz"
        "sha256-t5xwAPGhuQUfGThedLsmtZEEp1Ljjo3Udhd5Ql3O67c="
        "BreezeX-RosePine-Linux";
  };
}
