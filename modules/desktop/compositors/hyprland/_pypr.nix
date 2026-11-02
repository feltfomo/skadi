{
  pyprland = {
    plugins = [
      "fetch_client_menu"
      "scratchpads"
    ];
  };
  fetch_client_menu = {
    # Fetched windows float in the middle of the focused monitor.
    engine = "fuzzel";
    center_on_fetch = true;
    margin = 60;
  };
  scratchpads = {
    centered = {
      lazy = true;
      animation = "fromTop";
      size = "100% 70%";
      max_size = "1600px 100%";
      # A 70% height leaves 15% on either side on the configured 1440p and 1080p monitors.
      margin = 216;
      monitor = {
        eDP-1 = {
          margin = 162;
        };
      };
    };
    spotify = {
      use = "centered";
      command = "spotify";
      class = "spotify";
    };
    thunar = {
      use = "centered";
      command = "thunar";
      class = "thunar";
    };
  };
}
