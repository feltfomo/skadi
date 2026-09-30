{
  inputs,
  program,
  rootPath,
  ...
}:
let
  packageFor =
    pkgs:
    pkgs.callPackage "${rootPath}/pkgs/serpantinum" {
      licenseFile = "${inputs.serpantinum}/LICENSE.md";
      upstream = inputs.serpantinum.packages.${pkgs.stdenv.hostPlatform.system}.default.override {
        quickshell = inputs.quickshell.packages.${pkgs.stdenv.hostPlatform.system}.default.withModules [
          pkgs.qt6.qt5compat
          pkgs.qt6.qtmultimedia
          pkgs.qt6.qtwebsockets
          pkgs.qt6.qtimageformats
        ];
      };
    };
  defaults = builtins.fromJSON (
    builtins.readFile "${inputs.serpantinum}/config/serpantinum/settings.json"
  );
  overrides = builtins.fromJSON (builtins.readFile "${rootPath}/configs/serpantinum/settings.json");
  settings = inputs.nixpkgs.lib.recursiveUpdate defaults overrides;
in
{
  flake-file.inputs.serpantinum = {
    url = "github:ilyamiro/serpantinum/9861a84d8a798dfd520102912db507773dc18971";
    inputs.nixpkgs.follows = "nixpkgs";
  };
  perSystem = { pkgs, ... }: {
    packages.serpantinum = packageFor pkgs;
  };
  den.aspects.serpantinum = program {
    hosts = [
      "khion"
      "lumi"
    ];
    pkg = packageFor;
    nixos = {
      imports = [ inputs.serpantinum.nixosModules.default ];
      programs.serpantinum.enable = true;
      security.polkit.enable = true;
      services.accounts-daemon.enable = true;
      services.upower.enable = true;
    };
    imports = [
      ({ pkgs, ... }: {
        home.packages = [
          pkgs.playerctl
          pkgs.libpulseaudio
        ];
      })
    ];
    files = [
      {
        # Replace the bundled display map rather than merging its disabled eDP-1.
        src = builtins.toFile "serpantinum-settings.json" (
          builtins.toJSON (settings // { inherit (overrides) display; })
        );
        dest = ".config/serpantinum/settings.json";
        representation = "writable";
        onConflict = "runtime-wins";
      }
    ];
    theme = {
      id = "serpantinum-shell";
      output = ".local/state/serpantinum/qs_colors.json";
      renderers.serpantinum.source = "${inputs.serpantinum}/src/assets/matugen/templates/serpantinum_matugen_colors.json.template";
    };
  };
}
