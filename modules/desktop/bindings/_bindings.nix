{ lib }:
let
  adapters = import ./_actions.nix { inherit lib; };
  supported = [
    "hyprland"
    "mango"
  ];
  modifiers = [
    "SUPER"
    "SHIFT"
    "CTRL"
    "ALT"
  ];
  check =
    condition: message: value:
    assert lib.assertMsg condition "bindings: ${message}";
    value;
  fields =
    label: allowed: value:
    check (
      builtins.isAttrs value && lib.subtractLists allowed (builtins.attrNames value) == [ ]
    ) "unknown or malformed ${label} fields" value;
  nonempty = value: builtins.isString value && value != "";
  unique = values: builtins.length values == builtins.length (lib.unique values);
  targetsFor =
    values:
    check (
      builtins.isList values
      && values != [ ]
      && unique values
      && builtins.all (value: builtins.elem value supported) values
    ) "targets must name hyprland or mango without duplicates" values;
  parseChord =
    chord:
    let
      parts = map (part: lib.strings.trim part) (lib.splitString "+" chord);
      key = lib.last parts;
      given = map lib.toUpper (lib.init parts);
      ordered = builtins.filter (modifier: builtins.elem modifier given) modifiers;
      mouse = {
        "mouse:middle" = {
          mango = "btn_middle";
          hyprland = "mouse:274";
        };
        "mouse:right" = {
          mango = "btn_right";
          hyprland = "mouse:273";
        };
        "mouse:left" = {
          mango = "btn_left";
          hyprland = "mouse:272";
        };
      };
      isMouse = builtins.hasAttr (lib.toLower key) mouse;
      checked =
        builtins.all nonempty parts
        && unique given
        && builtins.length ordered == builtins.length given
        && !(builtins.elem (lib.toUpper key) modifiers)
        && builtins.match "[a-zA-Z0-9_:.-]+" key != null
        && (!lib.hasPrefix "mouse:" (lib.toLower key) || isMouse);
    in
    check checked "invalid chord ${builtins.toJSON chord}" {
      inherit key isMouse;
      modifiers = ordered;
      id = lib.concatStringsSep "+" (ordered ++ [ (lib.toLower key) ]);
      hyprland = lib.concatStringsSep " + " (
        ordered ++ [ (if isMouse then mouse.${lib.toLower key}.hyprland else key) ]
      );
      mango = "${if ordered == [ ] then "NONE" else lib.concatStringsSep "+" ordered},${
        if isMouse then mouse.${lib.toLower key}.mango else key
      }";
    };
  routingFor =
    value:
    let
      root = fields "workspaceRouting" supported value;
      hypr = {
        selectBank = "focused-output";
        moveFollows = false;
        banks = [ ];
        first = 1;
        count = 10;
      }
      // fields "Hyprland routing" [ "selectBank" "moveFollows" "banks" "first" "count" ] (
        root.hyprland or { }
      );
      mango = {
        moveFollows = false;
        count = 9;
      }
      // fields "Mango routing" [ "moveFollows" "count" ] (root.mango or { });
      positive = number: builtins.isInt number && number > 0;
      banks = map (
        bank:
        let
          data = fields "workspace bank" [ "output" "first" "count" ] bank;
        in
        check (
          nonempty (data.output or null) && positive (data.first or null) && positive (data.count or null)
        ) "workspace banks need output, first and count" data
      ) hypr.banks;
      sorted = lib.sort (a: b: a.first < b.first) banks;
      disjoint =
        builtins.foldl'
          (state: bank: {
            end = bank.first + bank.count - 1;
            valid = state.valid && bank.first > state.end;
          })
          {
            end = 0;
            valid = true;
          }
          sorted;
    in
    check
      (
        builtins.isList hypr.banks
        && positive hypr.first
        && positive hypr.count
        && positive mango.count
        && mango.count <= 9
        && builtins.isBool hypr.moveFollows
        && builtins.isBool mango.moveFollows
        && builtins.elem hypr.selectBank [
          "focused-output"
          "global"
        ]
        && (hypr.selectBank != "global" || banks == [ ])
        && unique (map (bank: bank.output) banks)
        && disjoint.valid
      )
      "invalid workspace routing, duplicate outputs or overlapping banks"
      {
        hyprland = hypr // {
          inherit banks;
        };
        inherit mango;
      };
  directionKeys = {
    right = {
      arrows = "Right";
      vim = "l";
    };
    left = {
      arrows = "Left";
      vim = "h";
    };
    down = {
      arrows = "Down";
      vim = "j";
    };
    up = {
      arrows = "Up";
      vim = "k";
    };
  };
  longestFirst = lib.sort (a: b: builtins.stringLength a > builtins.stringLength b);
  lua = lib.generators.toLua { multiline = false; };
  keys = rec {
    bind =
      specification:
      if builtins.isString specification || builtins.isList specification then
        action:
        bind {
          chord = specification;
          inherit action;
        }
      else
        let
          value = fields "bind" [ "chord" "action" "targets" ] specification;
        in
        check (value ? chord && value ? action) "a bind needs chord and action" (
          {
            _type = "binding";
            targets = null;
          }
          // value
        );
    inherit (adapters) native;
    directions =
      specification:
      let
        value = fields "direction group" [
          "modifiers"
          "keys"
          "directions"
          "action"
          "targets"
        ] specification;
        families =
          value.keys or [
            "arrows"
            "vim"
          ];
        selected =
          value.directions or [
            "right"
            "left"
            "down"
            "up"
          ];
      in
      check
        (
          builtins.isList (value.modifiers or null)
          && builtins.all builtins.isString value.modifiers
          && builtins.isFunction (value.action or null)
          && builtins.isList families
          && families != [ ]
          && unique families
          && builtins.all (
            family:
            builtins.elem family [
              "arrows"
              "vim"
            ]
          ) families
          && builtins.isList selected
          && selected != [ ]
          && unique selected
          && builtins.all (name: builtins.isString name && builtins.hasAttr name directionKeys) selected
        )
        "direction groups need modifiers, an action function and valid key families/directions"
        (
          lib.concatMap (
            name:
            map (
              family:
              bind {
                chord = lib.concatStringsSep " + " (value.modifiers ++ [ directionKeys.${name}.${family} ]);
                action = value.action name;
                targets = value.targets or null;
              }
            ) families
          ) selected
        );
    numbered =
      specification:
      let
        value = fields "number group" [ "modifiers" "numbers" "action" "targets" ] specification;
      in
      check
        (
          builtins.isList (value.modifiers or null)
          && builtins.all builtins.isString value.modifiers
          && builtins.isFunction (value.action or null)
          && builtins.isList (value.numbers or null)
          && value.numbers != [ ]
          && unique value.numbers
          && builtins.all (number: builtins.isInt number && number >= 0 && number <= 9) value.numbers
        )
        "number groups need modifiers, digits 0 through 9 and an action function"
        (
          map (
            number:
            bind {
              chord = lib.concatStringsSep " + " (value.modifiers ++ [ (toString number) ]);
              action = value.action number;
              targets = value.targets or null;
            }
          ) value.numbers
        );
    define =
      specification:
      let
        value = fields "definition" [ "bindings" "groups" "targets" "workspaceRouting" ] specification;
        targets = targetsFor (value.targets or supported);
        routing = routingFor (value.workspaceRouting or { });
        groups = value.groups or [ ];
        entries = check (
          builtins.isList (value.bindings or [ ])
          && builtins.isList groups
          && builtins.all builtins.isList groups
        ) "bindings and groups must be lists" ((value.bindings or [ ]) ++ lib.concatLists groups);
        normalized = lib.concatMap (
          entry:
          let
            data = check (
              builtins.isAttrs entry && (entry._type or null) == "binding"
            ) "expected keys.bind in a definition" entry;
            chords = if builtins.isList data.chord then data.chord else [ data.chord ];
            selected = targetsFor (if data.targets == null then targets else data.targets);
          in
          check
            (
              chords != [ ]
              && builtins.all nonempty chords
              && builtins.all (target: builtins.elem target targets) selected
            )
            "bind chords must be nonempty and targets must belong to the definition"
            (
              map (chord: {
                chord = parseChord chord;
                action = check (
                  builtins.isAttrs data.action && (data.action._type or null) == "binding-action"
                ) "expected a binding action" data.action;
                targets = selected;
              }) chords
            )
        ) entries;
        compiled = map (
          entry:
          entry
          // {
            native = lib.genAttrs entry.targets (
              target:
              builtins.addErrorContext "while compiling ${entry.chord.hyprland} for ${target}" (
                check
                  (
                    !(builtins.elem entry.action.kind [
                      "window.drag"
                      "window.resize"
                    ])
                    || entry.chord.isMouse
                  )
                  "interactive drag and resize actions need a mouse chord"
                  (adapters.render target routing entry.action)
              )
            );
          }
        ) normalized;
        forTarget = target: builtins.filter (entry: builtins.elem target entry.targets) compiled;
        collisions = lib.concatMap (
          target:
          let
            counts = builtins.groupBy (entry: entry.chord.id) (forTarget target);
          in
          map (chord: "${target}: ${chord}") (
            builtins.attrNames (lib.filterAttrs (_: found: builtins.length found > 1) counts)
          )
        ) targets;
        rendered = lib.genAttrs targets (
          target:
          let
            lines = map (
              entry:
              if target == "mango" then
                "${if entry.chord.isMouse then "mousebind" else "bind"}=${entry.chord.mango},${entry.native.mango}"
              else
                "hl.bind(${lua entry.chord.hyprland}, ${entry.native.hyprland})"
            ) (forTarget target);
          in
          if target == "mango" then
            "key_mode=default\n" + lib.concatStringsSep "\n" (longestFirst lines) + "\n"
          else
            "return function(B)\nB.configureRouting(${lua routing.hyprland})\n"
            + lib.concatStringsSep "\n" (longestFirst lines)
            + "\nend\n"
        );
      in
      builtins.deepSeq routing (
        builtins.deepSeq compiled (
          check (collisions == [ ]) "duplicate shortcuts: ${lib.concatStringsSep ", " collisions}" (
            rendered
            // {
              bindings = normalized;
              workspaceRouting = routing;
            }
          )
        )
      );
  };
in
{
  inherit keys;
  inherit (adapters) actions;
}
