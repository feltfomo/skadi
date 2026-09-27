{ inputs, ... }:
{
  # llm-agents already comes in through herdr, no second input declaration needed
  den.aspects.cline = {
    # cline keeps auth and task history in ~/.cline, nothing useful lands in .config
    persistence =
      { host, ... }:
      {
        users = builtins.mapAttrs (_: _: {
          directories = [ ".cline" ];
        }) host.users;
      };

    homeManager =
      { pkgs, ... }:
      {
        home.packages = [
          inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.cline
        ];
      };
  };
}
