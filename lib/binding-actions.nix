{ lib }:
let
  check =
    condition: message: value:
    assert lib.assertMsg condition "bindings: ${message}";
    value;
  text = value: builtins.isString value && value != "";
  fields =
    allowed: value:
    builtins.isAttrs value && lib.subtractLists allowed (builtins.attrNames value) == [ ];
  positive = value: builtins.isInt value && value > 0;
  lua = lib.generators.toLua { multiline = false; };
  action = kind: arguments: {
    _type = "binding-action";
    inherit kind arguments;
  };
  direction =
    kind: value:
    check (builtins.elem value [
      "right"
      "left"
      "down"
      "up"
    ]) "invalid direction" (action kind value);
  slot =
    kind: value: check (positive value) "workspace slot must be a positive integer" (action kind value);
  line =
    value:
    text value && !lib.hasInfix "\n" value && !lib.hasInfix "\r" value && !lib.hasInfix "," value;
  mangoArgument =
    value:
    let
      rendered = if builtins.isInt value || builtins.isFloat value then toString value else value;
    in
    check (
      builtins.isString rendered && (rendered == "" || line rendered)
    ) "Mango arguments cannot contain commas or newlines; use an executable script" rendered;
  native =
    target: value:
    if target == "hyprland" then
      check (fields [ "exec" "lua" ] value && builtins.length (builtins.attrNames value) == 1)
        "a Hyprland native action needs exactly one of exec or lua"
        (
          if value ? exec then
            check (text value.exec) "Hyprland exec must be nonempty text" "hl.dsp.exec_cmd(${lua value.exec})"
          else
            check (text value.lua) "Hyprland lua must be a callback expression" value.lua
        )
    else
      check (fields [ "exec" "command" "arguments" ] value) "unknown Mango native action field" (
        if value ? exec then
          check (
            builtins.attrNames value == [ "exec" ] && line value.exec
          ) "Mango exec must be a single command without commas or newlines" "spawn,${value.exec}"
        else
          let
            arguments = value.arguments or [ ];
          in
          check
            (
              text (value.command or null)
              && builtins.match "[a-zA-Z_][a-zA-Z0-9_]*" value.command != null
              && builtins.isList arguments
              && builtins.length arguments <= 5
            )
            "Mango native actions need a command and at most five arguments"
            (lib.concatStringsSep "," ([ value.command ] ++ map mangoArgument arguments))
      );
  fixed = {
    "window.maximize" = {
      mango = "togglemaximizescreen";
      hyprland = "B.maximize()";
    };
    "window.fullscreen" = {
      mango = "togglefullscreen";
      hyprland = ''hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle", layout_aware = true })'';
    };
    "window.floating" = {
      mango = "togglefloating";
      hyprland = "hl.dsp.window.float()";
    };
    "window.resize" = {
      mango = "moveresize,curresize";
      hyprland = "hl.dsp.window.resize()";
    };
    "window.drag" = {
      mango = "moveresize,curmove";
      hyprland = "hl.dsp.window.drag()";
    };
    "window.close" = {
      mango = "killclient";
      hyprland = "hl.dsp.window.close()";
    };
    "session.reload" = {
      mango = "reload_config";
      hyprland = ''hl.dsp.exec_cmd("hyprctl reload")'';
    };
    "session.overview" = {
      mango = "toggleoverview";
      hyprland = "B.overview";
    };
    "session.quit" = {
      mango = "quit";
      hyprland = "hl.dsp.exit()";
    };
  };
  layoutNames = {
    vertical-scroller = {
      mango = "vertical_scroller";
      hyprland = "scrolling";
      direction = "down";
    };
    scroller = {
      mango = "scroller";
      hyprland = "scrolling";
      direction = "right";
    };
    dwindle = {
      mango = "dwindle";
      hyprland = "dwindle";
      direction = "right";
    };
    monocle = {
      mango = "monocle";
      hyprland = "monocle";
      direction = "right";
    };
    master = {
      mango = "tile";
      hyprland = "master";
      direction = "right";
    };
  };
in
{
  actions = {
    exec = command: check (text command) "exec needs a nonempty command" (action "exec" command);
    window = {
      focus = direction "window.focus";
      swap = direction "window.swap";
      floating = action "window.floating" null;
      maximize = action "window.maximize" null;
      fullscreen = action "window.fullscreen" null;
      resize = action "window.resize" null;
      close = action "window.close" null;
      drag = action "window.drag" null;
    };
    workspace = {
      moveToSlot = slot "workspace.move";
      selectSlot = slot "workspace.select";
    };
    monitor = {
      focus = direction "monitor.focus";
      move = direction "monitor.move";
    };
    layout.select =
      name:
      check (builtins.isString name && builtins.hasAttr name layoutNames) "unknown shared layout name" (
        action "layout" name
      );
    scroll.columnWidth =
      width:
      check (
        (builtins.isInt width || builtins.isFloat width) && width >= 0.1 && width <= 1
      ) "column width must be between 0.1 and 1" (action "column-width" width);
    session = {
      overview = action "session.overview" null;
      reload = action "session.reload" null;
      quit = action "session.quit" null;
    };
  };
  native =
    implementations:
    check (
      fields [ "hyprland" "mango" ] implementations && implementations != { }
    ) "native actions need named hyprland or mango implementations" (action "native" implementations);
  render =
    target: routing: value:
    check (builtins.isAttrs value && (value._type or null) == "binding-action")
      "expected a binding action"
      (
        let
          inherit (value) kind;
          arg = value.arguments;
        in
        if kind == "native" then
          check (builtins.hasAttr target arg) "missing ${target} implementation" (native target arg.${target})
        else if builtins.hasAttr kind fixed then
          fixed.${kind}.${target}
        else if kind == "exec" then
          native target { exec = arg; }
        else if kind == "window.focus" then
          if target == "mango" then "focusdir,${arg}" else "B.focus(${lua arg})"
        else if kind == "window.swap" then
          if target == "mango" then "exchange_client,${arg}" else "B.swap(${lua arg})"
        else if kind == "monitor.focus" then
          if target == "mango" then "focusmon,${arg}" else "hl.dsp.focus({ monitor = ${lua arg} })"
        else if kind == "monitor.move" then
          if target == "mango" then "tagmon,${arg},0" else "B.monitor_move(${lua arg})"
        else if kind == "workspace.select" || kind == "workspace.move" then
          let
            policy = routing.${target};
            count = builtins.foldl' (current: bank: lib.min current bank.count) policy.count (
              policy.banks or [ ]
            );
            move = kind == "workspace.move";
          in
          check (arg <= count) "workspace slot ${toString arg} exceeds ${target}'s ${toString count} slots" (
            if target == "hyprland" then
              "B.workspace(${toString arg}, ${lua move})"
            else if !move then
              "view,${toString arg},0"
            else if policy.moveFollows then
              "tag,${toString arg},0"
            else
              "tagsilent,${toString arg}"
          )
        else if kind == "layout" then
          let
            selected = layoutNames.${arg};
          in
          if target == "mango" then
            "setlayout,${selected.mango}"
          else
            "B.layout(${lua selected.hyprland}, ${lua selected.direction})"
        else if kind == "column-width" then
          if target == "mango" then "set_proportion,${builtins.toJSON arg}" else "B.column_width(${lua arg})"
        else
          throw "bindings: unsupported action ${kind} for ${target}"
      );
}
