{
  den,
  inputs,
  lexicon,
  ...
}:
{
  flake-file.inputs.no-ai-slop = {
    flake = false;
    url = "github:petergyang/no-ai-slop/000650b156983f5159695b441477f4e63b25dc85";
  };

  den.aspects.codex = {
    includes = with den.aspects; [
      codex-skills
      codex-theme
      agents
    ];

    homeManager =
      { pkgs, ... }:
      let
        agents = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
        chatgpt = agents.chatgpt.override {
          chatgpt-unwrapped = agents.chatgpt.unwrapped.overrideAttrs (old: {
            buildInputs = (old.buildInputs or [ ]) ++ [ pkgs.tpm2-tss ];
          });
        };
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
          chatgpt
          codex
        ];
      };
  };

  den.aspects.codex-theme = lexicon {
    homeManager =
      { pkgs, lib, ... }:
      let
        setup = import ../../lib/theme-setup.nix { inherit pkgs; };
      in
      {
        home.activation.codexTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run ${setup}/bin/app-theme-setup codex
        '';
      };
    theme =
      { pkgs, ... }:
      let
        setup = import ../../lib/theme-setup.nix { inherit pkgs; };
      in
      {
        id = "codex";
        output = ".codex/themes/reactive.tmTheme";
        reload = "${setup}/bin/app-theme-setup codex";
        renderers = {
          noctalia = {
            source = ../../configs/codex/reactive.tmTheme;
            sharedWith = [
              "illogical-impulse"
              "serpantinum"
              "end4-pc"
              "dms"
            ];
          };
          caelestia.source = ../../configs/codex/caelestia.tmTheme;
        };
      };
  };

  den.aspects.codex-skills = lexicon {
    furnish.directories = [
      {
        source = "${inputs.no-ai-slop}/skills/no-ai-slop";
        destination = ".codex/skills/no-ai-slop";
      }
    ];
  };
}
