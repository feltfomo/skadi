{
  inputs,
  lexicon,
  ...
}:
{
  den.aspects.starship = lexicon {
    homeManager.programs.starship = {
      enable = true;
      enableFishIntegration = true;
    };
    theme =
      { pkgs, ... }:
      let
        toml = inputs.lexicon.lib.toml { inherit pkgs; };
        palette = import ./_palettes.nix;
      in
      {
        id = "starship";
        output = ".config/starship.toml";
        merge = {
          format = "toml";
          base = {
            format = "$directory$git_branch$git_status$package$character";
            right_format = "$git_state$cmd_duration";
            add_newline = false;
            palette = "reactive";
            palettes.reactive = { };
            directory = {
              style = "bold blue";
              truncation_length = 3;
              truncate_to_repo = false;
              read_only = " ro";
              format = "[$path]($style)[$read_only](red) ";
            };
            git_branch = {
              style = "purple";
              symbol = "";
              format = "[$branch]($style) ";
            };
            git_status = {
              style = "yellow";
              format = "([$all_status$ahead_behind]($style) )";
              conflicted = "=";
              untracked = "?";
              modified = "!";
              staged = "+";
              deleted = "x";
              stashed = "*";
              renamed = "r";
              ahead = "↑$count";
              behind = "↓$count";
              diverged = "↑$ahead_count↓$behind_count";
            };
            package = {
              symbol = "";
              style = "dimmed cyan";
              format = "[$version]($style) ";
            };
            git_state.format = "[$state( $progress_current/$progress_total)](yellow) ";
            cmd_duration = {
              min_time = 2000;
              format = "[$duration](dimmed white)";
            };
            character = {
              success_symbol = "[❯](green)";
              error_symbol = "[❯](red)";
              vimcmd_symbol = "[❮](blue)";
            };
          };
        };
        template = toml.render palette;
        placedAs = "reactive.toml";
      };
  };
}
