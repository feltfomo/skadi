{ inputs, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      manifests =
        map (host: inputs.self.nixosConfigurations.${host}.config.lexicon.furnish.manifestData)
          [
            "khion"
            "lumi"
          ];
      skillDestinations = map (directory: "/home/feltfomo/${directory}/herdr/SKILL.md") [
        ".claude/skills"
        ".agents/skills"
        ".codex/skills"
      ];
      herdrEntries = builtins.filter (
        entry: builtins.elem entry.filesystemIdentity.destination skillDestinations
      );
      correct =
        entries:
        let
          links = builtins.filter (
            entry:
            entry.target.kind == "external"
            && pkgs.lib.hasPrefix "/home/feltfomo/Projects/skills/" entry.target.path
          ) entries;
          destinations = map (entry: entry.filesystemIdentity.destination) links;
          skills = herdrEntries entries;
        in
        builtins.length links == 9
        && builtins.length (pkgs.lib.unique destinations) == 9
        && builtins.all (
          entry:
          entry.authority.identity == "feltfomo"
          && pkgs.lib.hasPrefix "/home/feltfomo/Projects/skills/subphase-" entry.target.path
        ) links
        && builtins.length skills == 3
        && builtins.length (pkgs.lib.unique (map (entry: entry.filesystemIdentity.destination) skills)) == 3
        && builtins.all (
          entry: entry.authority.identity == "feltfomo" && entry.target.kind == "retained"
        ) skills;
      herdr = inputs.llm-agents.packages.${system}.herdr;
    in
    {
      checks = pkgs.lib.optionalAttrs (system == "x86_64-linux") {
        skills =
          assert builtins.all correct manifests;
          pkgs.runCommand "skills-check"
            {
              nativeBuildInputs = [
                pkgs.python3
                pkgs.bash
                pkgs.git
              ];
            }
            ''
              python3 ${../../tests/bootstrap-repos.py} ${../../scripts/bootstrap-repo.sh}
              ${pkgs.lib.concatMapStringsSep "\n" (
                entries:
                pkgs.lib.concatMapStringsSep "\n" (
                  entry: "cmp ${pkgs.lib.escapeShellArg entry.target.path} ${herdr.src}/skills/herdr/SKILL.md"
                ) (herdrEntries entries)
              ) manifests}
              touch "$out"
            '';
      };
    };
}
