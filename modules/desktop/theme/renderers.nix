{ lib, ... }:
{
  options.skadi.theme.noctaliaCompatibleRenderers = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    readOnly = true;
    default = [
      "illogical-impulse"
      "serpantinum"
      "end4-pc"
      "dms"
    ];
    description = "Lexicon theme renderers whose template syntax matches noctalia's, so a noctalia renderer source can be passed to them unchanged through `sharedWith`.";
  };
}
