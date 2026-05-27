{ ... }:
{
  nix = {
    # automatic garbage collection (from wiki)
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
    # deduplicate store with hardlinks on a schedule
    # better than auto-optimise-store which slows down every build
    optimise.automatic = true;
  };
}
