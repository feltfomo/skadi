{ den, ... }:
{
  den.aspects.grandpa = {
    # omit primary-user to keep this account out of wheel and networkmanager.
    includes = [
      den.batteries.define-user
      den.aspects.ghostty
      den.aspects.chrome
      den.aspects.obsidian
    ];

    nixos =
      { pkgs, config, ... }:
      {
        sops.secrets."grandpa-password".neededForUsers = true;
        skadi.provision.secrets.grandpa-password = {
          method = "mkpasswd";
          prompt = "login password for grandpa";
        };

        users.users.grandpa = {
          description = "Grandpa";
          isNormalUser = true;
          group = "grandpa";
          shell = pkgs.bash;
          hashedPasswordFile = config.sops.secrets."grandpa-password".path;
        };
        users.groups.grandpa = { };
      };

    homeManager =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        ini = pkgs.formats.ini { };
        defaults = {
          "menus/applications-kmenuedit.menu" = pkgs.writeText "grandpa-menu-edits" ''
            <Menu><Name>Applications</Name></Menu>
          '';
          kdeglobals = ini.generate "grandpa-kdeglobals" {
            General.font = "Noto Sans,12,-1,5,50,0,0,0,0,0";
            KDE.SingleClick = false;
          };
          kcminputrc = ini.generate "grandpa-kcminputrc" {
            Mouse = {
              cursorTheme = "Win10OS";
              cursorSize = 48;
            };
          };
          "kicker-extra-favoritesrc" = ini.generate "grandpa-favorites" {
            General = {
              IgnoreDefaults = true;
              Prepend = "google-chrome.desktop;org.kde.dolphin.desktop;org.kde.discover.desktop;systemsettings.desktop;";
            };
          };
          "mimeapps.list" = ini.generate "grandpa-mimeapps" {
            "Default Applications" = {
              "text/html" = "google-chrome.desktop;";
              "x-scheme-handler/http" = "google-chrome.desktop;";
              "x-scheme-handler/https" = "google-chrome.desktop;";
              "application/pdf" = "google-chrome.desktop;";
            };
          };
        };
        appDirectories = [
          "${config.xdg.dataHome}/flatpak/exports/share/applications"
          "${pkgs.kdePackages.systemsettings}/share/applications"
          "${config.home.profileDirectory}/share/applications"
          "${pkgs.kdePackages.discover}/share/applications"
          "${pkgs.kdePackages.dolphin}/share/applications"
          "${config.xdg.dataHome}/applications"
        ];
      in
      {
        home.packages = [
          pkgs.zed-editor
          pkgs.papirus-icon-theme
          pkgs.win10-cursors
        ];
        home.file.".icons/Win10OS".source = "${pkgs.win10-cursors}/share/icons/Win10OS";

        # seed writable preferences once so settings changes survive rebuilds.
        home.activation.plasmaDefaults = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          set -euo pipefail
          run mkdir -p "$HOME/.config/menus"
          ${lib.concatStringsSep "\n" (
            lib.mapAttrsToList (name: source: ''
              if [ ! -e "$HOME/.config/${name}" ] && [ ! -L "$HOME/.config/${name}" ]; then
                run install -m 600 ${source} "$HOME/.config/${name}"
              fi
            '') defaults
          )}
        '';

        # apply the initial palette and cursor once so later settings changes survive.
        home.activation.plasmaAppearance = lib.hm.dag.entryAfter [ "plasmaDefaults" ] ''
          set -euo pipefail
          if [ ! -e ${lib.escapeShellArg "${config.xdg.stateHome}/skadi/plasma-appearance"} ]; then
            run env QT_QPA_PLATFORM=offscreen \
              XDG_DATA_DIRS="${pkgs.kdePackages.breeze}/share:''${XDG_DATA_DIRS:-/run/current-system/sw/share}" \
              ${pkgs.kdePackages.plasma-workspace}/bin/plasma-apply-colorscheme BreezeDark
            run env QT_QPA_PLATFORM=offscreen \
              XCURSOR_PATH="${pkgs.win10-cursors}/share/icons:''${XCURSOR_PATH:-/run/current-system/sw/share/icons}" \
              ${pkgs.kdePackages.plasma-workspace}/bin/plasma-apply-cursortheme Win10OS
            run mkdir -p ${lib.escapeShellArg "${config.xdg.stateHome}/skadi"}
            run touch ${lib.escapeShellArg "${config.xdg.stateHome}/skadi/plasma-appearance"}
          fi
        '';

        home.activation.plasmaIcons = lib.hm.dag.entryAfter [ "plasmaDefaults" ] ''
          set -euo pipefail
          if [ ! -e ${lib.escapeShellArg "${config.xdg.stateHome}/skadi/plasma-icons"} ]; then
            run ${pkgs.kdePackages.kconfig}/bin/kwriteconfig6 \
              --file ${lib.escapeShellArg "${config.xdg.configHome}/kdeglobals"} \
              --group Icons --key Theme --notify Papirus-Dark
            run mkdir -p ${lib.escapeShellArg "${config.xdg.stateHome}/skadi"}
            run touch ${lib.escapeShellArg "${config.xdg.stateHome}/skadi/plasma-icons"}
          fi
        '';

        xdg.configFile."menus/plasma-applications.menu".text = ''
          <!DOCTYPE Menu PUBLIC "-//freedesktop//DTD Menu 1.0//EN"
            "http://www.freedesktop.org/standards/menu-spec/1.0/menu.dtd">
          <Menu>
            <Name>Applications</Name>
            <DefaultDirectoryDirs/>
            ${lib.concatMapStringsSep "\n" (path: "<AppDir>${path}</AppDir>") appDirectories}
            <Include><All/></Include>
            <Layout><Merge type="menus"/><Merge type="files"/></Layout>
            <MergeFile>applications-kmenuedit.menu</MergeFile>
          </Menu>
        '';

        systemd.user.services.flathub = {
          Unit.Description = "Set up the user's Flathub app source";
          Service = {
            Type = "oneshot";
            ExecStart = "${pkgs.flatpak}/bin/flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo";
            RemainAfterExit = true;
            Restart = "on-failure";
            RestartSec = 30;
          };
          Install.WantedBy = [ "default.target" ];
        };
      };
  };
}
