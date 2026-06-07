{
  lib,
  rootPath,
  ...
}:
let
  program = import ../_lib/program.nix { inherit lib; };
in
{
  den.aspects.noctalia = program {
    files = [
      {
        dest = ".config/noctalia/theme.toml";
        src = "${rootPath}/configs/noctalia/theme.toml";
      }
      {
        dest = ".config/noctalia/shell.toml";
        src = "${rootPath}/configs/noctalia/shell.toml";
      }
      {
        dest = ".config/noctalia/bar.toml";
        src = "${rootPath}/configs/noctalia/bar.toml";
      }
      {
        dest = ".config/noctalia/dock.toml";
        src = "${rootPath}/configs/noctalia/dock.toml";
      }
    ];
  };
}
