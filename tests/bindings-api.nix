{ lib }:
let
  inherit (import ../lib/bindings.nix { inherit lib; }) keys actions;
  fails = value: !(builtins.tryEval (builtins.deepSeq value true)).success;
  define = bindings: keys.define { inherit bindings; };
  shared = define [ (keys.bind "SUPER + t" (actions.exec "kitty")) ];
  groups = keys.define {
    groups = [
      (keys.directions {
        modifiers = [ "SUPER" ];
        keys = [
          "arrows"
          "vim"
        ];
        action = actions.window.focus;
      })
      (keys.numbered {
        modifiers = [ "SUPER" ];
        numbers = lib.range 1 9;
        action = actions.workspace.selectSlot;
      })
    ];
  };
  separate = define [
    (keys.bind {
      chord = "SUPER + e";
      targets = [ "hyprland" ];
      action = keys.native { hyprland.lua = ''function() hl.exec_cmd("thunar") end''; };
    })
    (keys.bind {
      chord = "SUPER + e";
      targets = [ "mango" ];
      action = keys.native {
        mango = {
          command = "spawn";
          arguments = [ "kitty" ];
        };
      };
    })
    (keys.bind {
      chord = "SUPER + 0";
      targets = [ "hyprland" ];
      action = actions.workspace.selectSlot 10;
    })
  ];
  follows = keys.define {
    workspaceRouting.mango.moveFollows = true;
    bindings = [ (keys.bind "SUPER + SHIFT + 1" (actions.workspace.moveToSlot 1)) ];
  };
  silent = define [ (keys.bind "SUPER + SHIFT + 1" (actions.workspace.moveToSlot 1)) ];
  alias = define [ (keys.bind [ "SUPER + e" "SUPER + Return" ] (actions.exec "kitty")) ];
  global = keys.define {
    targets = [ "hyprland" ];
    workspaceRouting.hyprland = {
      selectBank = "global";
      first = 21;
      count = 10;
    };
    bindings = [ (keys.bind "SUPER + 0" (actions.workspace.selectSlot 10)) ];
  };
in
assert builtins.length groups.bindings == 17;
assert builtins.length alias.bindings == 2;
assert lib.hasInfix "spawn,kitty" shared.mango;
assert lib.hasInfix ''hl.dsp.exec_cmd("kitty")'' shared.hyprland;
assert lib.hasInfix "function() hl.exec_cmd" separate.hyprland;
assert !(lib.hasInfix "SUPER,0," separate.mango);
assert lib.hasInfix "tag,1,0" follows.mango;
assert lib.hasInfix "tagsilent,1" silent.mango;
assert global.workspaceRouting.hyprland.first == 21;
assert fails (define [
  (keys.bind "CTRL + SUPER + t" actions.window.close)
  (keys.bind "super + ctrl + T" actions.window.close)
]);
assert fails (define [
  (keys.bind "SUPER + e" (actions.exec "kitty"))
  (keys.bind [ "Super + E" "SUPER + Return" ] actions.window.close)
]);
assert fails (define [ (keys.bind "SUPER + e" (keys.native { hyprland.exec = "kitty"; })) ]);
assert fails (define [ (keys.bind "SUPER + 0" (actions.workspace.selectSlot 10)) ]);
assert fails (define [ (keys.bind "SUPER +" actions.window.close) ]);
assert fails (define [ (keys.bind "SUPER + SUPER + e" actions.window.close) ]);
assert fails (define [ (keys.bind "UNKNOWN + e" actions.window.close) ]);
assert fails (define [
  (keys.bind {
    chord = "SUPER + e";
    targets = [ "niri" ];
    action = actions.window.close;
  })
]);
assert fails (define [
  (keys.bind {
    chord = "SUPER + e";
    target = "mango";
    action = actions.window.close;
  })
]);
assert fails (define [ (keys.bind "SUPER + e" actions.window) ]);
assert fails (define [ (keys.bind "SUPER + e" actions.window.drag) ]);
assert fails (define [
  (keys.bind "SUPER + e" (
    keys.native {
      mango = {
        command = "spawn";
        arguments = [ "one,two" ];
      };
      hyprland.exec = "kitty";
    }
  ))
]);
assert fails (
  keys.define {
    groups = [
      (keys.directions {
        modifiers = [ "SUPER" ];
        keys = [
          "vim"
          "unknown"
        ];
        action = actions.window.focus;
      })
    ];
  }
);
assert fails (
  keys.define {
    groups = [
      (keys.numbered {
        modifiers = [ "SUPER" ];
        numbers = [ 10 ];
        action = actions.workspace.selectSlot;
      })
    ];
  }
);
assert fails (
  keys.define {
    workspaceRouting.hyprland.banks = [
      {
        output = "DP-1";
        first = 1;
        count = 10;
      }
      {
        output = "DP-2";
        first = 10;
        count = 10;
      }
    ];
  }
);
assert fails (
  keys.define {
    workspaceRouting.hyprland.banks = [
      {
        output = "DP-1";
        first = 1;
        count = 10;
      }
      {
        output = "DP-1";
        first = 11;
        count = 10;
      }
    ];
  }
);
true
