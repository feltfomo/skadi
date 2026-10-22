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
      correct =
        entries:
        let
          links = builtins.filter (
            entry:
            entry.target.kind == "external"
            && pkgs.lib.hasPrefix "/home/feltfomo/Projects/skills/" entry.target.path
          ) entries;
          destinations = map (entry: entry.filesystemIdentity.destination) links;
        in
        builtins.length links == 9
        && builtins.length (pkgs.lib.unique destinations) == 9
        && builtins.all (
          entry:
          entry.authority.identity == "feltfomo"
          && pkgs.lib.hasPrefix "/home/feltfomo/Projects/skills/subphase-" entry.target.path
        ) links;
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
              python3 ${../../tests/skills-bootstrap.py} ${../../scripts/bootstrap-skills.sh}
              touch "$out"
            '';
      };
    };
}
