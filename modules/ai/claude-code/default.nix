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
    # the github plugin expands GITHUB_PERSONAL_ACCESS_TOKEN into its
    # Authorization header. reading the secret at launch keeps it out of
    # other shells. hosts without the secret leave it unset, so the plugin
    # fails to connect with a malformed Authorization header.
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
            --run 'if [ -r /run/secrets/github-mcp-token ]; then export GITHUB_PERSONAL_ACCESS_TOKEN="$(< /run/secrets/github-mcp-token)"; fi'
        '';
      };
    nixos = [
      {
        hosts = [
          "khion"
          "lumi"
        ];
        value = {
          sops.secrets."github-mcp-token" = {
            owner = "feltfomo";
            mode = "0400";
          };
          skadi.provision.secrets.github-mcp-token = {
            method = "paste";
            prompt = "GitHub personal access token for the github MCP server";
          };
        };
      }
    ];
    homeManager =
      { pkgs, lib, ... }:
      let
        setup = pkgs.skadi-app-theme-setup;
      in
      {
        home.activation.claudeCodeTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run ${setup}/bin/app-theme-setup claude-code
        '';
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
