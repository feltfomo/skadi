{ inputs, lib, ... }:
{
  flake.modules.nixos.khion-modules = {
    imports =
      (lib.filesystem.listFilesRecursive ./_hosts/khion) ++ (with inputs.self.modules.nixos; [ shared ]);
  };
}
