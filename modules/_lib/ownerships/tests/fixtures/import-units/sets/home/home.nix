{ marker, ... }:
{
  label = "home fixture";
  users = [ "feltfomo" ];

  programs.ownershipsImporter.enable = true;
  home.sessionVariables.OWNERSHIPS_IMPORTER = marker;
}
