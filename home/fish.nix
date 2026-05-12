{ ... }:
{
  programs.fish = {
    enable = true;
    interactiveShellInit = ''
      fastfetch
    '';
  };
}
