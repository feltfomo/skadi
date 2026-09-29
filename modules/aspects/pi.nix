{
  inputs,
  program,
  ...
}:
{
  flake-file.inputs.pi-extensions = {
    url = "github:feltfomo/pi-extensions";
    inputs = {
      nixpkgs.follows = "nixpkgs";
      home-manager.follows = "home-manager";
    };
  };

  den.aspects.pi = program {
    pkg = pkgs: inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.pi;
    imports = [
      inputs.pi-extensions.homeManagerModules.status-lines
      {
        programs.pi-coding-agent.extensions.status-lines.enable = true;
      }
    ];
  };
}
