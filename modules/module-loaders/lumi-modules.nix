{ inputs, lib, ... }:
{
  flake.modules.nixos.lumi-modules = {
    imports =
      (lib.filesystem.listFilesRecursive ./_hosts/lumi) ++ (with inputs.self.modules.nixos; [ shared ]);
  };
}
