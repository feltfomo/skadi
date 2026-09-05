{ program, rootPath, ... }:
let
  u = code: builtins.fromJSON ''"\u${code}"'';
  u2 = high: low: builtins.fromJSON ''"\u${high}\u${low}"'';
  esc = u "001b";
  rainbowGlyph = u2 "db83" "de95";
  rainbowLine = builtins.concatStringsSep "" (
    map (color: "${esc}[${color}m${rainbowGlyph}  ") [
      "31"
      "32"
      "33"
      "34"
      "35"
      "36"
      "37"
      "30"
      "91"
      "92"
      "93"
      "94"
      "95"
      "96"
      "97"
      "90"
    ]
  );
in
{
  den.aspects.fastfetch = program {
    imports = [
      {
        programs.fastfetch = {
          enable = true;
          settings = {
            "$schema" = "https://github.com/fastfetch-cli/fastfetch/raw/master/doc/json_schema.json";
            logo = {
              type = "file";
              source = "~/.config/fastfetch/logo.txt";
              color = {
                "1" = "magenta";
                "2" = "cyan";
              };
              padding = {
                top = 3;
                left = 3;
                right = 3;
              };
            };
            display.separator = " ";
            modules = [
              {
                type = "custom";
                format = "{#magenta}╭──────────┤os/system├──────────{#}";
              }
              {
                type = "os";
                key = "├─${u "f313"} ";
                keyColor = "magenta";
              }
              {
                type = "kernel";
                key = "├─${u "f17c"} ";
                keyColor = "magenta";
              }
              {
                type = "uptime";
                key = "├─${u "f017"} ";
                keyColor = "magenta";
              }
              {
                type = "custom";
                format = "{#magenta}╰───────────────────────────────{#}";
              }
              "break"
              {
                type = "custom";
                format = "{#cyan}╭──────────┤hardware├───────────{#}";
              }
              {
                type = "cpu";
                key = "├─${u "f4bc"} ";
                keyColor = "cyan";
              }
              {
                type = "gpu";
                key = "├─${u "e266"} ";
                keyColor = "cyan";
              }
              {
                type = "memory";
                key = "├─${u "efc5"} ";
                keyColor = "cyan";
              }
              {
                type = "swap";
                key = "├─${u2 "db83" "dfb6"} ";
                keyColor = "cyan";
              }
              {
                type = "disk";
                key = "├─${u "f0c7"} ";
                keyColor = "cyan";
              }
              {
                type = "battery";
                key = "├─${u2 "db84" "dea3"} ";
                keyColor = "cyan";
              }
              {
                type = "custom";
                format = "{#cyan}╰───────────────────────────────{#}";
              }
              "break"
              {
                type = "custom";
                format = "{#red}╭──────────┤environment├────────{#}";
              }
              {
                type = "packages";
                key = "├─${u2 "db80" "dfd6"} ";
                keyColor = "red";
              }
              {
                type = "shell";
                key = "├─${u "ebca"} ";
                keyColor = "red";
              }
              {
                type = "terminal";
                key = "├─${u "ebc7"} ";
                keyColor = "red";
              }
              {
                type = "wm";
                key = "├─${u2 "db84" "dcac"} ";
                keyColor = "red";
              }
              {
                type = "custom";
                format = "{#red}╰───────────────────────────────{#}";
              }
              {
                type = "custom";
                format = rainbowLine;
              }
            ];
          };
        };
      }
    ];
    files = [
      {
        src = "${rootPath}/configs/fastfetch/logo.txt";
        dest = ".config/fastfetch/logo.txt";
      }
    ];
  };
}
