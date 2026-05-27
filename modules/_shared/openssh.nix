{ ... }:
{
  services.openssh = {
    enable = true;
    settings = {
      # disable password auth, require keys
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };
}
