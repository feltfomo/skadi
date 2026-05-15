{ ... }:
{
  flake.modules.nixos.shared =
    { lib, ... }:
    {
      imports = lib.filesystem.listFilesRecursive ./_shared;
    };
}
