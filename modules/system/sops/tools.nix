{ lexicon, ... }:
{
  den.aspects.sops-tools = lexicon {
    package =
      pkgs:
      pkgs.writeScriptBin "sops-edit" ''
        #!${pkgs.nushell}/bin/nu
        ${builtins.readFile ./sops-edit.nu}
      '';
  };
}
