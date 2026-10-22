{ program, ... }:
{
  den.aspects.skills =
    { user, ... }:
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
    in
    program {
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
