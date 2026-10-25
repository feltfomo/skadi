# shared shortcuts use mango's key choices; native compositor logic stays in its own config.
# see ../../lib/bindings.md for actions, groups, workspace slots and native bindings.
{
  lib,
  hostName ? "khion",
}:
let
  inherit (import ../../lib/bindings.nix { inherit lib; }) keys actions;
  scratchpad =
    name: appId: command:
    keys.native {
      hyprland.exec = "pypr-client toggle ${name}";
      mango = {
        command = "toggle_named_scratchpad";
        arguments = [
          appId
          "none"
          command
        ];
      };
    };
in
keys.define {
  workspaceRouting = {
    hyprland = {
      selectBank = "focused-output";
      moveFollows = false;
      banks = lib.optionals (hostName == "khion") [
        {
          output = "DP-1";
          first = 1;
          count = 10;
        }
        {
          output = "DP-2";
          first = 11;
          count = 10;
        }
      ];
    };
    mango = {
      moveFollows = false;
      count = 9;
    };
  };

  bindings = [
    (keys.bind {
      chord = "SUPER + Tab";
      targets = [ "mango" ];
      action = keys.native { mango.command = "toggleoverview"; };
    })
    (keys.bind {
      chord = "SUPER + SHIFT + 0";
      targets = [ "hyprland" ];
      action = actions.workspace.moveToSlot 10;
    })
    (keys.bind {
      chord = "SUPER + 0";
      targets = [ "hyprland" ];
      action = actions.workspace.selectSlot 10;
    })
    (keys.bind [ "SUPER + SHIFT + comma" "SUPER + SHIFT + minus" ] (
      actions.exec "noctalia msg volume-down"
    ))
    (keys.bind "SUPER + comma" (
      scratchpad "settings" "dev.noctalia.Noctalia" "noctalia msg settings-open"
    ))
    (keys.bind [ "SUPER + SHIFT + period" "SUPER + SHIFT + equal" ] (
      actions.exec "noctalia msg volume-up"
    ))
    (keys.bind "SUPER + Space" (actions.exec "noctalia msg panel-toggle launcher"))
    (keys.bind "SUPER + c" (actions.exec "noctalia msg panel-toggle clipboard"))
    (keys.bind "SUPER + w" (actions.exec "noctalia msg panel-toggle wallpaper"))
    (keys.bind "SUPER + CTRL + v" (actions.layout.select "vertical-scroller"))
    (keys.bind "ALT + Tab" (actions.exec "noctalia msg window-switcher"))
    (keys.bind "Print" (actions.exec "noctalia msg screenshot-region"))
    (keys.bind "SUPER + s" (scratchpad "spotify" "spotify" "spotify"))
    (keys.bind "SUPER + CTRL + s" (actions.layout.select "scroller"))
    (keys.bind "SUPER + CTRL + d" (actions.layout.select "dwindle"))
    (keys.bind "SUPER + CTRL + o" (actions.layout.select "monocle"))
    (keys.bind "SUPER + CTRL + m" (actions.layout.select "master"))
    (keys.bind "SUPER + e" (scratchpad "thunar" "thunar" "thunar"))
    (keys.bind "SUPER + a" (actions.exec "noctalia msg annotate"))
    (keys.bind "SUPER + ALT + d" (actions.scroll.columnWidth 0.5))
    (keys.bind "SUPER + ALT + f" (actions.scroll.columnWidth 1.0))
    (keys.bind "SUPER + SHIFT + f" actions.window.fullscreen)
    (keys.bind "SUPER + mouse:right" actions.window.resize)
    (keys.bind "SUPER + mouse:left" actions.window.drag)
    (keys.bind "SUPER + v" actions.window.floating)
    (keys.bind "SUPER + f" actions.window.maximize)
    (keys.bind "SUPER + t" (actions.exec "kitty"))
    (keys.bind "SUPER + r" actions.session.reload)
    (keys.bind "SUPER + q" actions.window.close)
    (keys.bind "SUPER + m" actions.session.quit)
  ];

  groups = [
    (keys.directions {
      modifiers = [
        "SUPER"
        "SHIFT"
        "ALT"
      ];
      keys = [
        "arrows"
        "vim"
      ];
      action = actions.monitor.move;
    })
    (keys.directions {
      modifiers = [
        "SUPER"
        "ALT"
      ];
      keys = [
        "arrows"
        "vim"
      ];
      action = actions.window.swap;
    })
    (keys.directions {
      modifiers = [
        "SUPER"
        "CTRL"
      ];
      directions = [
        "right"
        "left"
      ];
      keys = [
        "arrows"
        "vim"
      ];
      action = actions.monitor.focus;
    })
    (keys.directions {
      modifiers = [ "SUPER" ];
      keys = [
        "arrows"
        "vim"
      ];
      action = actions.window.focus;
    })
    (keys.numbered {
      modifiers = [
        "SUPER"
        "SHIFT"
      ];
      numbers = lib.range 1 9;
      action = actions.workspace.moveToSlot;
    })
    (keys.numbered {
      modifiers = [ "SUPER" ];
      numbers = lib.range 1 9;
      action = actions.workspace.selectSlot;
    })
  ];
}
