{ lexicon, inputs, ... }:
let
  checkoutFor = user: "/home/${user.name}/Projects/skills";
in
{
  den.aspects.agents = lexicon {
    furnish = {
      links = { user, ... }: [
        {
          source = checkoutFor user;
          names = [
            "agentic-workflow-subagent"
            "agentic-workflow"
          ];
          destinations = [
            ".claude/skills"
            ".agents/skills"
            ".codex/skills"
          ];
        }
        # the global instructions link into the checkout so edits there apply without a rebuild.
        {
          source = "${checkoutFor user}/instructions/CLAUDE.md";
          destination = ".claude/CLAUDE.md";
        }
        {
          source = "${checkoutFor user}/instructions/AGENTS.md";
          destination = ".codex/AGENTS.md";
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
