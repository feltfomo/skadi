{ inputs, ... }:
{
  imports = [ inputs.treefmt-nix.flakeModule ];

  perSystem = {
    # nix fmt and the formatting check both run treefmt
    treefmt = {
      projectRootFile = "flake.nix";
      programs = {
        nixfmt.enable = true;
        deadnix.enable = true;
        statix.enable = true;
        stylua.enable = true;
      };
      # nixfmt runs last so it reflows what deadnix and statix rewrite
      settings.formatter.nixfmt.priority = 1;
    };
  };
}
