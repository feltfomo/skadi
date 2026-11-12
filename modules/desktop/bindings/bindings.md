# Shared desktop bindings

This local Nix helper declares shortcuts shared by Hyprland and MangoWM. The shortcut file says which key invokes an action. The adapters translate that action into each compositor's config.

Use it for shortcuts you want to maintain together. Keep compositor-specific control flow in Hyprland Lua or Mango's native config. A binding can also target one compositor when keeping it beside the shared bindings makes it easier to find.

The supported target names are `hyprland` and `mango`. This is an internal skadi API.

| File | What to edit there |
| --- | --- |
| [\_binds.nix](_binds.nix) | Shortcuts, groups, workspace routing and locally named native actions |
| [workspace.lua](../compositors/hyprland/config/lib/workspace.lua) | Runtime workspace bank selection and movement |
| [binds.lua](../compositors/hyprland/config/config/binds.lua) | Plain Hyprland-only shortcuts, one per line, and the generated binding load |
| [lib/binds.lua](../compositors/hyprland/config/lib/binds.lua) | Hyprland runtime behavior the shared bindings call |
| [binds.conf](../compositors/mango/config/binds.conf) | Additional native Mango bindings after the generated include |
| [\_actions.nix](_actions.nix) | Shared actions and their native implementations |
| [\_bindings.nix](_bindings.nix) | Expansion, validation and rendering |

## Add a shared shortcut

The declaration imports the helper and returns a definition:

```nix
{ lib }:
let
  inherit (import ./_bindings.nix { inherit lib; }) keys actions;
in
keys.define {
  bindings = [
    (keys.bind "SUPER + Space" (actions.exec "noctalia msg panel-toggle launcher"))
    (keys.bind "SUPER + e" (actions.exec "thunar"))
    (keys.bind "SUPER + q" actions.window.close)
  ];
}
```

Add routine shortcuts to `bindings` in the existing declaration. `actions.exec` takes command text. Install the command through the appropriate aspect. For compound shell commands, use an executable script so both compositors invoke the same program.

A chord has zero or more modifiers followed by one key. The supported modifiers are `SUPER`, `SHIFT`, `CTRL` and `ALT`. Write `Print` for an unmodified key. Use `plus` for the plus key. Modifier order and letter case don't distinguish shortcuts during collision checks.

One action can have several shortcuts:

```nix
(keys.bind [ "SUPER + Return" "SUPER + e" ] (actions.exec "kitty"))
```

Mouse chords use `mouse:middle`, `mouse:right` or `mouse:left`:

```nix
(keys.bind "SUPER + mouse:right" actions.window.resize)
(keys.bind "SUPER + mouse:left" actions.window.drag)
```

The helper checks chord structure. The compositor still checks whether a keyboard keysym exists.

## Expand directions and numbers

Put group declarations in `groups`. A direction group passes `right`, `left`, `down` and `up` to its action function. Both key families below are explicit, and they are also the defaults:

```nix
(keys.directions {
  modifiers = [ "SUPER" "ALT" ];
  keys = [ "arrows" "vim" ];
  action = actions.window.swap;
})

(keys.directions {
  modifiers = [ "SUPER" ];
  keys = [ "arrows" "vim" ];
  action = actions.window.focus;
})
```

These produce Right/L, Left/H, Down/J and Up/K shortcuts. Set `keys = [ "vim" ];` to use only Vim keys. Restrict a group with `directions = [ "right" "left" ];`, for example when focusing monitors.

A numbered group passes each digit to its action function:

```nix
(keys.numbered {
  modifiers = [ "SUPER" "SHIFT" ];
  numbers = lib.range 1 9;
  action = actions.workspace.moveToSlot;
})

(keys.numbered {
  modifiers = [ "SUPER" ];
  numbers = lib.range 1 9;
  action = actions.workspace.selectSlot;
})
```

`numbers` contains physical digits from zero through nine. It isn't a workspace range. Bind key `0` to slot ten explicitly, as shown below. Groups also accept `targets` to restrict their expansion to one compositor.

## Route workspace slots

Workspace actions take a logical slot, starting at one. The compositor adapter resolves that slot into a workspace ID or tag. This keeps monitor routing out of individual shortcuts.

```nix
workspaceRouting = {
  hyprland = {
    banks = [
      { output = "DP-1"; first = 1; count = 10; }
      { output = "DP-2"; first = 11; count = 10; }
    ];
  };
  mango = {
    count = 9;
  };
};
```

Slot three selects workspace 3 on DP-1, workspace 13 on DP-2, or tag 3 in Mango. Each configured Hyprland bank creates persistent workspace rules for its output. Overlapping banks and repeated output names are errors.

The skadi declaration supplies these banks on khion. Lumi has no output banks. Hyprland's fallback range starts at `first = 1` and has `count = 10` slots. The fallback also applies to an output without a configured bank. Both fields are configurable. For a single global range, leave `banks` empty.

The shared number groups use slots one through nine. Hyprland's additional slot uses a target-specific binding:

```nix
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
```

On khion, key `0` addresses workspace 10 on DP-1 or workspace 20 on DP-2. A shared slot-ten action would fail because Mango has nine slots. When banks have different sizes, shared slot actions must fit every bank and the fallback range.

`moveToSlot` sends the window without changing the viewed workspace. Hyprland uses `follow = false`; Mango uses `tagsilent`. `followToSlot` sends the window and switches to its workspace. Hyprland uses `follow = true`; Mango uses `tag`. Mango's second `tag` argument controls monitor synchronization, not whether focus follows.

`step` goes to the adjacent workspace on the focused monitor, with `up` toward lower numbers and `down` toward higher ones. It stops at the first and last slot. Mango wraps instead if `tag_carousel` is enabled.

## Use native actions

The record form of `keys.bind` accepts `chord`, `action` and optional `targets`. Bindings inherit the definition's targets, which default to both compositors. Every action needs an implementation for every selected target.

For one Hyprland action:

```nix
(keys.bind {
  chord = "SUPER + CTRL + e";
  targets = [ "hyprland" ];
  action = keys.native {
    hyprland.lua = ''
      function()
        local workspace = hl.get_active_workspace()
        if workspace and workspace.tiled_layout == "scrolling" then
          hl.dispatch(hl.dsp.layout("center"))
        end
      end
    '';
  };
})
```

`hyprland.lua` is a Lua expression returning a callback, including a dispatcher such as `hl.dsp.window.close()`. Use `hyprland.exec` for command text. Choose exactly one of them.

For one Mango action:

```nix
(keys.bind {
  chord = "SUPER + CTRL + e";
  targets = [ "mango" ];
  action = keys.native {
    mango = {
      command = "toggle_named_scratchpad";
      arguments = [ "spotify" "none" "spotify" ];
    };
  };
})
```

Mango accepts `exec`, or `command` with optional `arguments`. Arguments are strings or numbers, with at most five entries. Commas and newlines cannot be represented in this helper's Mango command parameters. Put complicated commands in a script or maintain the binding in native config.

To share one shortcut with different implementations, provide both `hyprland` and `mango` under `keys.native`. Name a reusable action in the declaration's `let` block, as the current Spotify action does. A missing implementation is an error, even if you request only the other rendered output.

## Keep Lua and native config where they help

Add a Hyprland-only shortcut as one line in `modules/desktop/compositors/hyprland/config/config/binds.lua`. A command string runs through `exec`; any other action is a Hyprland dispatcher. An optional third entry passes bind options such as `{ repeating = true }`:

```lua
local binds = {
  { "SUPER + X", "kitty --class btop -e btop" },
  { "SUPER + Z", hl.dsp.window.pseudo() },
}
```

These chords aren't checked against the shared ones, so pick keys `_binds.nix` doesn't use.

Add runtime-dependent Hyprland logic to `binds.lua` as a Lua function, and put helpers the shared bindings call in `modules/desktop/compositors/hyprland/config/lib/binds.lua`. For example:

```lua
hl.bind("SUPER + CTRL + e", function()
  local workspace = hl.get_active_workspace()
  if workspace and workspace.tiled_layout == "scrolling" then
    hl.dispatch(hl.dsp.layout("center"))
  end
end)
```

Add Mango-only bindings to `modules/desktop/compositors/mango/config/binds.conf`, after its `source` line:

```ini
bind=SUPER+CTRL,e,spawn,thunar
```

These files remain native compositor config. Use them for modes, release bindings, gestures, device rules or longer Lua behavior. Promote an action into the helper when several shared shortcuts need the same behavior.

Collision checks cover bindings declared through this helper. They can't inspect additional Lua or native config, so check those files before reusing a chord. Two target-specific declarations can share a chord when their targets don't overlap.

## Available shared actions

| Action | Argument or behavior |
| --- | --- |
| `actions.workspace.moveToSlot` | Logical slot, resolved through workspace routing |
| `actions.workspace.followToSlot` | Logical slot, resolved through workspace routing |
| `actions.workspace.selectSlot` | Logical slot, resolved through workspace routing |
| `actions.workspace.step` | `down` or `up`, one workspace at a time |
| `actions.scroll.columnWidth` | Width from 0.1 through 1, for scrolling layouts |
| `actions.window.fullscreen` | Toggle layout-aware fullscreen |
| `actions.window.maximize` | Toggle full column width in Hyprland scrolling, or maximization elsewhere |
| `actions.window.floating` | Toggle floating state |
| `actions.session.reload` | Reload the compositor config |
| `actions.window.resize` | Interactive mouse resize |
| `actions.monitor.focus` | Direction to the next monitor |
| `actions.monitor.move` | Move the focused window to the monitor in that direction and follow it, entering Hyprland scrolling columns from the crossed edge |
| `actions.window.focus` | Direction, with Hyprland scrolling-aware focus |
| `actions.layout.select` | `vertical-scroller`, `scroller`, `dwindle`, `monocle` or `master`, on the focused workspace until the next config reload on Hyprland |
| `actions.window.close` | Close the focused window |
| `actions.session.quit` | End the compositor session |
| `actions.window.swap` | Direction to exchange windows |
| `actions.window.drag` | Interactive mouse move |
| `actions.exec` | Command text |

## Validate a change

Hyprland's generated output is a Lua module loaded by `modules/desktop/compositors/hyprland/config/config/binds.lua`, which passes it the scrolling and workspace callbacks from `lib/binds.lua`. Mango's output is included by `modules/desktop/compositors/mango/config/binds.conf`. Keep those entry points when editing the adapters.

The compositor aspects import `_binds.nix` with the host name. The returned `hyprland` and `mango` strings become the generated config files. Output lines are sorted longest first. Sorting doesn't assign shortcut priority. Duplicate chords on the same target fail evaluation.

Run `praxis check` from the repo's dev shell. It runs `nix flake check`, which builds the hosts, so evaluation catches target restrictions, missing implementations, chord collisions, workspace limits, routing errors and malformed native actions. It doesn't run any Hyprland Lua, so a change that affects focus, layouts, window placement or the Lua callbacks still needs a session check.
