{
  program,
  rootPath,
  inputs,
  ...
}:
{
  # theme.output = whole config.toml, herdr can't split files
  den.aspects.herdr = program {
    pkg = pkgs: inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.herdr;
    theme = {
      id = "herdr";
      output = ".config/herdr/config.toml";
      reload = "herdr server reload-config";
      renderers = {
        noctalia = {
          source = "${rootPath}/configs/herdr/themes/reactive.toml";
          sharedWith = [
            "dms"
            "illogical-impulse"
            "end4-pc"
          ];
        };
        caelestia.source = "${rootPath}/configs/herdr/themes/caelestia.toml";
      };
    };
  };
}
