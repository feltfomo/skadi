{ den, inputs, ... }:
{
  flake-file.inputs.silent-sddm = {
    url = "github:uiriansan/SilentSDDM";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  den.aspects.silent-sddm = {
    includes = [ den.aspects.sddm ];

    nixos =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        theme = inputs.silent-sddm.packages.${pkgs.stdenv.hostPlatform.system}.default.override {
          theme = "default";
          theme-overrides =
            lib.mapAttrs' (
              name: session:
              lib.nameValuePair "User.${name}" {
                preferred-session = session;
              }
            ) config.skadi.silent-sddm.preferredSessions
            // {
              LockScreen.display = false;
              "LoginScreen.LoginArea.Username".font-size = 20;
              "LoginScreen.LoginArea.PasswordInput" = {
                width = 280;
                height = 42;
                font-size = 16;
              };
              "LoginScreen.MenuArea.Popups" = {
                font-size = 14;
                item-height = 38;
              };
            };
        };
      in
      {
        options.skadi.silent-sddm.preferredSessions = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
          description = "Preferred login session name for each SilentSDDM user.";
        };

        config = {
          environment.systemPackages = [ theme ];
          fonts.packages = [ pkgs.redhat-official-fonts ];

          services.displayManager.sddm = {
            theme = "silent";
            wayland = {
              enable = true;
              compositor = "kwin";
            };
            extraPackages = theme.propagatedBuildInputs;
            settings.General = {
              GreeterEnvironment = "QT_WAYLAND_SHELL_INTEGRATION=layer-shell,QML2_IMPORT_PATH=${theme}/share/sddm/themes/silent/components/,QT_IM_MODULE=qtvirtualkeyboard";
              InputMethod = "qtvirtualkeyboard";
            };
          };
        };
      };
  };
}
