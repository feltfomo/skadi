{
  den,
  inputs,
  program,
  ...
}:
{
  flake-file.inputs.no-ai-slop = {
    flake = false;
    url = "github:petergyang/no-ai-slop/000650b156983f5159695b441477f4e63b25dc85";
  };

  den.aspects.codex = {
    includes = [ den.aspects.codex-skills ];

    # the wiped root must keep auth tokens and rollout history across boots.
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
        # the daemon copies a complete package from the running CLI executable.
        codex = pkgs.runCommand "codex-packaged-${agents.codex.version}" { } ''
          mkdir -p "$out/bin" "$out/libexec"
          cp -rL ${agents.codex}/libexec/codex "$out/libexec/"
          chmod -R u+w "$out/libexec/codex"
          mkdir -p "$out/libexec/codex/codex-path"
          cp ${pkgs.ripgrep}/bin/rg "$out/libexec/codex/codex-path/rg"
          printf '%s\n' '${
            builtins.toJSON {
              version = agents.codex.version;
              target = pkgs.stdenv.hostPlatform.config;
              entrypoint = "bin/codex";
            }
          }' > "$out/libexec/codex/codex-package.json"
          ln -s ../libexec/codex/bin/codex "$out/bin/codex"
          ln -s ../libexec/codex/bin/codex-code-mode-host "$out/bin/codex-code-mode-host"
          ln -s ../libexec/codex/bin/logs_client "$out/bin/logs_client"
          ln -s ${agents.codex}/share "$out/share"
        '';
      in
      {
        home.packages = [
          codex
          agents.chatgpt
        ];
      };
  };

  den.aspects.codex-skills = program {
    directories = [
      {
        src = "${inputs.no-ai-slop}/skills/no-ai-slop";
        dest = ".codex/skills/no-ai-slop";
      }
    ];
  };
}
