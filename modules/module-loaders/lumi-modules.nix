{ inputs, lib, ... }:
{
  flake.modules.nixos.lumi-modules = {
    imports =
      (lib.filesystem.listFilesRecursive ../_host-modules/lumi)
      ++ (with inputs.self.modules.nixos; [ shared ]);
  };
}
