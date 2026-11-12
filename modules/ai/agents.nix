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
            "technical-writing"
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
      directories = [
        # the skill comes from the same checkout as the installed binary, so its commands match.
        {
          source = "${inputs.herdr}/skills/herdr";
          destination = ".claude/skills/herdr";
        }
        {
          source = "${inputs.herdr}/skills/herdr";
          destination = ".agents/skills/herdr";
        }
        {
          source = "${inputs.herdr}/skills/herdr";
          destination = ".codex/skills/herdr";
        }
      ];
    };
  };
}
