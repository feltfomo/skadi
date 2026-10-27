{
  files = {
    "audio.toml" = {
      audio = {
        enable_overdrive = true;
      };
    };
    "bar.toml" = {
      bar = {
        default = {
          background_opacity = 0.8899999801069498;
          capsule_fill = "surface";
          capsule_foreground = "primary";
          end = [
            "temp"
            "ram"
            "cpu"
            "tray"
            "volume"
            "wallpaper"
            "notifications"
            "control-center"
          ];
          margin_edge = 0;
          margin_ends = 0;
          margin_opposite_edge = 1;
          radius = 0;
          start = [
            "workspaces"
            "media"
            "bar"
          ];
        };
      };
      widget = {
        bar = {
          type = "miguelfm/ai-triage:bar";
        };
        clock = {
          format = "{:%H:%M:%S}";
        };
        control-center = {
          custom_image = "";
          scale = 1.1500000000000001;
        };
        volume = {
          show_label = false;
        };
        workspaces = {
          anchor = true;
          capsule = true;
          capsule_opacity = 0.0;
          capsule_padding = 0;
          capsule_radius = 0;
          focused_output_only = true;
          hide_when_empty = true;
        };
      };
    };
    "control_center.toml" = {
      control_center = {
        sidebar = "full";
        sidebar_section = "full";
        width = 900;
      };
    };
    "desktop_widgets.toml" = {
      desktop_widgets = {
        schema_version = 2;
        widget_order = [
          "desktop-widget-0000000000000001"
          "desktop-widget-0000000000000005"
          "desktop-widget-0000000000000006"
        ];
        grid = {
          cell_size = 16;
          major_interval = 4;
          visible = true;
        };
        widget = {
          desktop-widget-0000000000000001 = {
            box_height = 176.0;
            box_width = 384.0;
            cx = 256.0;
            cy = 856.0;
            output = "DP-2";
            placement_height = 1440.0;
            placement_width = 2560.0;
            rotation = 0.0;
            type = "media_player";
            settings = {
              bands = 32;
              layout = "horizontal";
              show_when_idle = true;
            };
          };
          desktop-widget-0000000000000005 = {
            box_height = 448.0;
            box_width = 640.0;
            cx = 384.0;
            cy = 1200.0;
            output = "DP-2";
            placement_height = 1440.0;
            placement_width = 2560.0;
            rotation = 0.0;
            type = "calendar";
          };
          desktop-widget-0000000000000006 = {
            box_height = 192.0;
            box_width = 384.0;
            cx = 2302.0;
            cy = 1328.0;
            output = "DP-2";
            placement_height = 1440.0;
            placement_width = 2560.0;
            rotation = 0.0;
            type = "clock";
          };
        };
      };
    };
    "dock.toml" = {
      dock = {
        background_opacity = 0.6;
        border_width = 1.0;
        enabled = false;
        launcher_position = "start";
        margin_edge = 10;
        pinned = [
          "steam"
          "spotify"
          "equibop"
          "zen-twilight"
        ];
        show_dots = true;
      };
    };
    "lockscreen_widgets.toml" = {
      lockscreen_widgets = {
        enabled = false;
        schema_version = 2;
        widget_order = [
          "lockscreen-login-box@DP-2"
          "lockscreen-login-box@DP-1"
        ];
        grid = {
          cell_size = 16;
          major_interval = 4;
          visible = true;
        };
        widget = {
          "lockscreen-login-box@DP-1" = {
            box_height = 196.0;
            box_width = 810.0;
            cx = 1280.0;
            cy = 1317.0;
            output = "DP-1";
            placement_height = 1440.0;
            placement_width = 2560.0;
            rotation = 0.0;
            type = "login_box";
            settings = {
              center_password_text = false;
              layout = "regular";
              show_caps_lock = true;
              show_keyboard_layout = true;
              show_login_button = true;
              show_media = true;
              show_session_buttons = true;
              show_unlock_hint = true;
              show_weather = true;
            };
          };
          "lockscreen-login-box@DP-2" = {
            box_height = 196.0;
            box_width = 810.0;
            cx = 1280.0;
            cy = 1317.0;
            output = "DP-2";
            placement_height = 1440.0;
            placement_width = 2560.0;
            rotation = 0.0;
            type = "login_box";
            settings = {
              center_password_text = false;
              layout = "regular";
              show_caps_lock = true;
              show_keyboard_layout = true;
              show_login_button = true;
              show_media = true;
              show_session_buttons = true;
              show_unlock_hint = true;
              show_weather = true;
            };
          };
        };
      };
    };
    "plugins.toml" = {
      plugin_settings = {
        "miguelfm/ai-triage" = {
          panel_placement = "floating";
          panel_position = "center";
        };
      };
    };
    "shell.toml" = {
      shell = {
        app_icon_color = "secondary";
        avatar_path = "/home/feltfomo/main_pfp.jpeg";
        clipboard_history_max_entries = 100.0;
        font_family = "Maple Mono NF";
        launch_apps_as_systemd_services = true;
        password_style = "random";
        polkit_agent = true;
        screen_time_enabled = true;
        settings_expand_all_groups = true;
        settings_window_translucent = true;
        telemetry_enabled = false;
        greeter_sync = {
          auto_sync = true;
        };
        launcher = {
          app_grid = true;
          session_search = true;
        };
        panel = {
          control_center_position = "center";
          clipboard_placement = "floating";
          launcher_placement = "floating";
          open_near_click_launcher = true;
          transparency_mode = "soft";
          wallpaper_placement = "floating";
        };
        screenshot = {
          confirm_region = true;
          directory = "/home/feltfomo/Pictures/Screenshots";
          pipe_command = "satty";
        };
        window_switcher = {
          mru = true;
        };
      };
    };
    "theme.toml" = {
      theme = {
        community_palette = "Oxocarbon";
        mode = "dark";
        source = "wallpaper";
        wallpaper_scheme = "m3-content";
        templates = {
          builtin_ids = [ ];
          community_ids = [ ];
          enable_community_templates = false;
        };
      };
    };
    "wallpaper.toml" = {
      wallpaper = {
        directory = "/home/feltfomo/Wallpapers";
        transition_on_startup = true;
        default = {
          path = "/home/feltfomo/Wallpapers/Pictures/23.png";
        };
        last = {
          path = "/home/feltfomo/Wallpapers/Pictures/23.png";
        };
        monitors = {
          DP-1 = {
            path = "/home/feltfomo/Wallpapers/Pictures/23.png";
          };
          DP-2 = {
            path = "/home/feltfomo/Wallpapers/Pictures/23.png";
          };
        };
      };
    };
  };
  profiles = {
    hyprland = {
      include = {
        files = [ "../../../" ];
      };
      bar = {
        default = {
          background_opacity = 0.6499999854713678;
        };
      };
      desktop_widgets = {
        widget = {
          desktop-widget-0000000000000001 = {
            box_height = 192.0;
            box_width = 512.0;
            cx = 2240.0;
            cy = 1136.0;
            settings = {
              background_opacity = 0.65;
              background_padding = 20;
              background_radius = 0;
            };
          };
          desktop-widget-0000000000000005 = {
            settings = {
              background_opacity = 0.65;
              background_radius = 0;
              show_events = false;
            };
          };
          desktop-widget-0000000000000006 = {
            box_width = 512.0;
            cx = 2240.0;
            type = "audio_visualizer";
            settings = {
              background_opacity = 0.65;
              background_padding = 0;
              background_radius = 0;
              bands = 76;
              show_wave = false;
              show_when_idle = true;
            };
          };
        };
      };
      notification = {
        background_opacity = 0.6499999854713678;
      };
      osd = {
        background_opacity = 0.6499999854713678;
      };
      shell = {
        panel = {
          transparency_mode = "glass";
        };
      };
      wallpaper = {
        default = {
          path = "/home/feltfomo/Wallpapers/Pictures/41.jpg";
        };
        last = {
          path = "/home/feltfomo/Wallpapers/Pictures/41.jpg";
        };
        monitors = {
          DP-1 = {
            path = "/home/feltfomo/Wallpapers/Pictures/41.jpg";
          };
          DP-2 = {
            path = "/home/feltfomo/Wallpapers/Pictures/41.jpg";
          };
        };
      };
    };
    mangowm = {
      include = {
        files = [ "../../../" ];
      };
    };
  };
}
