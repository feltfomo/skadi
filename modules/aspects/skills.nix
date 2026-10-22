{ program, inputs, ... }:
{
  den.aspects.skills =
    { user, host, ... }:
    let
      names = [
        "subphase-orchestrator"
        "subphase-implementer"
        "subphase-architect"
      ];
      directories = [
        ".claude/skills"
        ".agents/skills"
        ".codex/skills"
      ];
      checkout = "/home/${user.name}/Projects/skills";
      herdr = inputs.llm-agents.packages.${host.system}.herdr;
    in
    program {
      directories = map (directory: {
        src = "${herdr.src}/skills/herdr";
        dest = "${directory}/herdr";
      }) directories;
      links = builtins.concatMap (
        directory:
        map (name: {
          target = "${checkout}/${name}";
          dest = "${directory}/${name}";
        }) names
      ) directories;
      imports = [
        (
          { pkgs, ... }:
          let
            bootstrap = pkgs.writeShellApplication {
              name = "bootstrap-skills";
              runtimeInputs = [
                pkgs.coreutils
                pkgs.openssh
                pkgs.git
              ];
              text = builtins.readFile ../../scripts/bootstrap-skills.sh;
            };
          in
          {
            systemd.user.services.bootstrap-skills = {
              Unit.Description = "Prepare the shared skills checkout";
              Service = {
                Type = "oneshot";
                ExecStart = "${bootstrap}/bin/bootstrap-skills ${checkout} git@github.com:feltfomo/skills.git";
              };
              Install.WantedBy = [ "default.target" ];
            };
          }
        )
      ];
    };
}
