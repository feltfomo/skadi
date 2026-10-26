{
  inputs,
  lexicon,
  ...
}:
let
  packageFor =
    pkgs:
    pkgs.callPackage ./_package {
      licenseFile = "${inputs.serpantinum}/LICENSE.md";
      upstream = inputs.serpantinum.packages.${pkgs.stdenv.hostPlatform.system}.default.override {
        quickshell = inputs.quickshell.packages.${pkgs.stdenv.hostPlatform.system}.default.withModules (
          with pkgs.qt6;
          [
            qtimageformats
            qtmultimedia
            qtwebsockets
            qt5compat
          ]
        );
      };
    };
  defaults = builtins.fromJSON (
    builtins.readFile "${inputs.serpantinum}/config/serpantinum/settings.json"
  );
  overrides = builtins.fromJSON (builtins.readFile ./config/settings.json);
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
  den.aspects.serpantinum = lexicon {
    hosts = [
      "khion"
      "lumi"
    ];
    package = packageFor;
    nixos = [
      {
        value = {
          imports = [ inputs.serpantinum.nixosModules.default ];
          programs.serpantinum.enable = true;
          security.polkit.enable = true;
          services.accounts-daemon.enable = true;
          services.upower.enable = true;
        };
      }
    ];
    homeManager.imports = [
      ({ pkgs, ... }: {
        home.packages = with pkgs; [
          libpulseaudio
          playerctl
        ];
      })
    ];
    furnish.files = [
      {
        # Replace the bundled display map rather than merging its disabled eDP-1.
        source = builtins.toFile "serpantinum-settings.json" (
          builtins.toJSON (settings // { inherit (overrides) display; })
        );
        destination = ".config/serpantinum/settings.json";
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
