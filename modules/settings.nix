{ ... }:
{
  flake.nixosModules.settings =
    { ... }:
    {
      # enable experimental features, put wheel group in trusted-users, and enabled auto-optimise-store.
      nix.settings = {
        experimental-features = [
          "nix-command"
          "flakes"
        ];
        trusted-users = [ "@wheel" ];
        auto-optimise-store = true;
      };

      # allow unfree packages
      nixpkgs.config.allowUnfree = true;

      # set time zone and locale
      time.timeZone = "America/Los_Angeles";
      i18n.defaultLocale = "en_US.UTF-8";
    };
}
