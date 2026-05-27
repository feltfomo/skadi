{ ... }:
{
  # enable experimental features, put wheel group in trusted-users, and enabled auto-optimise-store.
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
      "pipe-operator"
    ];
    trusted-users = [ "@wheel" ];
    # prevents hanging on offline caches
    connect-timeout = 5;
  };

  # allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # set time zone and locale
  time.timeZone = "America/Los_Angeles";
  i18n.defaultLocale = "en_US.UTF-8";
}
