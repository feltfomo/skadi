{ ... }:
{
  flake.nixosModules.feltfomo =
    { pkgs, ... }:
    {
      # set feltfomo user
      users.users.feltfomo = {
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

        groups.feltfomo = { };
      };
    };
}
