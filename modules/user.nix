{ ... }:
{
  flake.nixosModules.user =
    { pkgs, ... }:
    {
      users = {
        # main user
        users.feltfomo = {
          isNormalUser = true;
          group = "feltfomo";
          hashedPassword = "$y$j9T$HT.mVqk50c03QSEv1rqlP0$5albZpdKB3hIndg.ecMfZ2ZxaDPEwDx5AbZKLaY9tY8";
          shell = pkgs.fish;

          # sudo, network, and video groups
          extraGroups = [
            "wheel"
            "networkmanager"
            "video"
          ];
        };

        users.grandpa = {
          isNormalUser = true;
          group = "grandpa";
          hashedPassword = "$y$j9T$EmyKMur/y5oRy1GBxFY28.$P55.D5.ua.d7NbKpJfh4Q2K4YjAoOQaMlQULxHTOlT8";
          shell = pkgs.bash;
        };
        # user group
        groups.feltfomo = { };
        groups.grandpa = { };
      };
    };
}
