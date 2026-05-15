{ inputs, ... }:
{
  # module to load khions unique and shared modules
  flake.modules.nixos.khion-modules =
    { lib, ... }:
    {
      imports =
        (lib.filesystem.listFilesRecursive ./_hosts/khion) ++ (with inputs.self.modules.nixos; [ shared ]);
    };

  # module to load lumis unique and shared modules
  flake.modules.nixos.lumi-modules =
    { lib, ... }:
    {
      imports =
        (lib.filesystem.listFilesRecursive ./_hosts/lumi) ++ (with inputs.self.modules.nixos; [ shared ]);
    };
}
