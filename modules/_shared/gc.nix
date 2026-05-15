{ ... }:
{
  nix = {
    # automatic garbage collection (from wiki)
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };
}
