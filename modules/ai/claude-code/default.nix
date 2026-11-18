{
  den,
  inputs,
  lexicon,
  ...
}:
{
  den.aspects.claude-code.includes = [ den.aspects.claude-code-cli ];

  den.aspects.claude-code-cli = {
    includes = [ den.aspects.agents ];
  }
  // lexicon {
    # the github plugin reads GITHUB_PERSONAL_ACCESS_TOKEN. reading the
    # secret at launch keeps it out of other shells.
    package =
      pkgs:
      let
        claude = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-code;
      in
      pkgs.symlinkJoin {
        name = "claude-code-${claude.version}";
        inherit (claude) pname version meta;
        paths = [ claude ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram "$out/bin/claude" \
            --run 'if [ -r /run/secrets/github-token ]; then export GITHUB_PERSONAL_ACCESS_TOKEN="$(< /run/secrets/github-token)"; fi'
        '';
      };
    homeManager =
      {
        config,
        pkgs,
        lib,
        ...
      }:
      let
        setup = pkgs.skadi-app-theme-setup;
        # the keep-warm watcher lives in the skills checkout beside the hooks that write its
        # records, so an edit there applies without a rebuild. its README explains the hooks, the
        # watcher and the stop rule.
        keepWarm = "${config.home.homeDirectory}/Projects/skills/hooks/keep-warm.py";
        herdr = inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default;
      in
      {
        home.activation.claudeCodeTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run ${setup}/bin/app-theme-setup claude-code
        '';

        systemd.user.services.claude-keep-warm = {
          Unit = {
            Description = "Poke idle Claude Code agents before their prompt cache expires";
            ConditionPathExists = keepWarm;
          };
          Service = {
            Type = "oneshot";
            ExecStart = "${pkgs.python3}/bin/python3 -I ${keepWarm} watch --herdr ${herdr}/bin/herdr";
          };
        };
        # a 30 second tick lands every poke within 30 seconds of the watcher's 54 minute mark.
        systemd.user.timers.claude-keep-warm = {
          Unit.Description = "Run the Claude Code keep-warm watcher every 30 seconds";
          Timer = {
            OnBootSec = "30s";
            OnUnitActiveSec = "30s";
            AccuracySec = "1s";
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    theme =
      { pkgs, ... }:
      let
        setup = pkgs.skadi-app-theme-setup;
      in
      {
        id = "claude-code";
        output = ".claude/themes/reactive.json";
        reload = "${setup}/bin/app-theme-setup claude-code";
        template = ./config/reactive.json;
      };
  };
}
