{ marker, ... }:
{
  label = "system fixture";
  hosts = [ "khion" ];

  services.ownershipsImporter = {
    enable = true;
    inherit marker;
  };
}
