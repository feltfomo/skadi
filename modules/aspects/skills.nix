{ lexicon, inputs, ... }:
let
  checkoutFor = user: "/home/${user.name}/Projects/skills";
in
{
  den.aspects.skills = lexicon {
    furnish = {
      links = { user, ... }: [
        {
          source = checkoutFor user;
          names = [
            "subphase-orchestrator"
            "subphase-implementer"
            "subphase-architect"
          ];
          destinations = [
            ".claude/skills"
            ".agents/skills"
            ".codex/skills"
          ];
        }
      ];
      directories =
        { host, ... }:
        let
          herdr = inputs.llm-agents.packages.${host.system}.herdr;
        in
        [
          {
            source = "${herdr.src}/skills/herdr";
            destination = ".claude/skills/herdr";
          }
          {
            source = "${herdr.src}/skills/herdr";
            destination = ".agents/skills/herdr";
          }
          {
            source = "${herdr.src}/skills/herdr";
            destination = ".codex/skills/herdr";
          }
        ];
    };
    homeManager =
      { pkgs, user, ... }:
      let
        bootstrap = pkgs.writeShellApplication {
          name = "bootstrap-skills";
          runtimeInputs = with pkgs; [
            coreutils
            openssh
            git
          ];
          text = builtins.readFile ../../scripts/bootstrap-skills.sh;
        };
      in
      {
        systemd.user.services.bootstrap-skills = {
          Unit.Description = "Prepare the shared skills checkout";
          Service = {
            Type = "oneshot";
            ExecStart = "${bootstrap}/bin/bootstrap-skills ${checkoutFor user} git@github.com:feltfomo/skills.git";
          };
          Install.WantedBy = [ "default.target" ];
        };
      };
  };
}
