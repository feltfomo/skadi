{
  inputs,
  lexicon,
  ...
}:
{
  flake-file.inputs.dms = {
    url = "github:AvengeMedia/DankMaterialShell";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  den.aspects.dms = lexicon {
    hosts = [
      "khion"
      "lumi"
    ];
    furnish.files = [
      {
        source = ./config/settings.json;
        destination = ".config/DankMaterialShell/settings.json";
        representation = "writable";
        onConflict = "source-wins";
      }
    ];
    nixos = _: [
      {
        value = {
          imports = [ inputs.dms.nixosModules.dank-material-shell ];
          programs.dank-material-shell = {
            enable = true;
            enableCalendarEvents = false;
            systemd = {
              enable = true;
              target = "niri.service";
            };
          };
        };
      }
    ];
  };
}
