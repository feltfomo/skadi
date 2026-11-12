{ lexicon, inputs, ... }:
let
  checkoutFor = user: "/home/${user.name}/Projects/skills";
in
{
  # no nixpkgs follows: its packages pin native libraries, such as aws-lc for codex, to the nixpkgs
  # it builds and tests against.
  flake-file.inputs.llm-agents.url = "github:numtide/llm-agents.nix";
  # built against that same nixpkgs, so codex and the other agents download instead of compiling.
  flake-file.nixConfig = {
    extra-substituters = [ "https://cache.numtide.com" ];
    extra-trusted-public-keys = [
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ];
  };

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
