{ inputs, ... }:
{
  # llm-agents already comes in through herdr, no second input declaration needed
  den.aspects.codex = {
    # auth tokens and rollout history live in ~/.codex, without this the wiped root
    # signs the cli out on every boot
    persistence =
      { host, ... }:
      {
        users = builtins.mapAttrs (_: _: {
          directories = [ ".codex" ];
        }) host.users;
      };

    homeManager =
      { pkgs, ... }:
      let
        agents = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
      in
      {
        # the desktop app ships as `chatgpt`, it wraps openai's own codex-app deb.
        # its electron state lands in ~/.config/ChatGPT, already persisted with .config
        home.packages = [
          agents.codex
          agents.chatgpt
        ];
      };
  };
}
