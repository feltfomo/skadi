{ ... }:
{
  home-manager.users.feltfomo.programs.btop = {
    enable = true;
    settings = {
      color_theme = "noctalia";
      theme_background = "false";
      true-color = true;
      rounded-corners = true;
      temp_scale = "fahrenheit";
    };
  };
}
