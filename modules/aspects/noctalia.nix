{
  program,
  rootPath,
  ...
}:
{
  den.aspects.noctalia = program {
    files = [
      {
        dest = ".config/noctalia/theme.toml";
        src = "${rootPath}/configs/noctalia/theme.toml";
      }
      {
        dest = ".config/noctalia/shell.toml";
        src = "${rootPath}/configs/noctalia/shell.toml";
      }
      {
        dest = ".config/noctalia/bar.toml";
        src = "${rootPath}/configs/noctalia/bar.toml";
      }
      {
        dest = ".config/noctalia/dock.toml";
        src = "${rootPath}/configs/noctalia/dock.toml";
      }
      {
        dest = ".config/noctalia/control_center.toml";
        src = "${rootPath}/configs/noctalia/control_center.toml";
      }
      {
        dest = ".config/noctalia/desktop_widgets.toml";
        src = "${rootPath}/configs/noctalia/desktop_widgets.toml";
      }
      {
        dest = ".config/noctalia/lockscreen_widgets.toml";
        src = "${rootPath}/configs/noctalia/lockscreen_widgets.toml";
      }
      {
        dest = ".config/noctalia/wallpaper.toml";
        src = "${rootPath}/configs/noctalia/wallpaper.toml";
      }
    ];
  };
}
