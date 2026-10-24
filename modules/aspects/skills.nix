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
  };
}
