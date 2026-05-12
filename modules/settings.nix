{ ... }:
{
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    trusted-users = [ "@wheel" ];
    trust-flakes = -[ "etc/skadi " ];
    auto-optimise-store = true;
  };

  nixpkgs.config.allowUnfree = true;

  time.timeZone = "America/Los_Angeles";
  i18n.defaultLocale = "en_US.UTF-8";
}
