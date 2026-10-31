{ lexicon, ... }:
{
  den.aspects.zed = lexicon {
    homeManager.programs.zed-editor = {
      enable = true;
      userSettings = {
        theme = {
          mode = "system";
          dark = "Reactive Dark";
          light = "Reactive Light";
        };
        enable_language_server = false;
        format_on_save = "off";
        remove_trailing_whitespace_on_save = true;
        ensure_final_newline_on_save = true;
        gutter.line_numbers = true;
        telemetry = {
          diagnostics = false;
          metrics = false;
        };
      };
    };
    theme = {
      id = "zed";
      output = ".config/zed/themes/reactive.json";
      reload = "zed --unstable-features theme-reload";
      template = ./config/themes/reactive.json;
    };
  };
}
