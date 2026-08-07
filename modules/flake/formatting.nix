{inputs, ...}: {
  imports = [inputs.treefmt-nix.flakeModule];

  perSystem = {
    # nix fmt and the formatting check both run treefmt
    treefmt = {
      projectRootFile = "flake.nix";
      programs = {
        nixfmt.enable = true;
        deadnix.enable = true;
        statix.enable = true;
        stylua.enable = true;
        rustfmt.enable = true;
        gofmt.enable = true;
        taplo.enable = true;
        yamlfmt.enable = true;
        mdformat.enable = true;
      };
      # nixfmt runs last so it reflows what deadnix and statix rewrite
      settings.formatter.nixfmt.priority = 1;
      # secrets/ is sops-managed. formatters stay out of it.
      settings.global.excludes = ["secrets/**"];
      # readme has a hand-maintained layout table mdformat mangles.
      settings.formatter.mdformat.excludes = ["README.md"];
    };
  };
}
