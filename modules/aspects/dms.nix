{
  inputs,
  program,
  rootPath,
  ...
}:
{
  flake-file.inputs.dms = {
    url = "github:AvengeMedia/DankMaterialShell";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  den.aspects.dms = program {
    hosts = [
      "khion"
      "lumi"
    ];
    files = [
      {
        src = "${rootPath}/configs/dms/settings.json";
        dest = ".config/DankMaterialShell/settings.json";
        representation = "writable";
        onConflict = "source-wins";
      }
    ];
    nixos = _: [
      {
        imports = [ inputs.dms.nixosModules.dank-material-shell ];
        programs.dank-material-shell = {
          enable = true;
          systemd = {
            enable = true;
            target = "niri.service";
          };
        };
      }
    ];
  };
}
