{
  den,
  inputs,
  program,
  ...
}:
{
  den.aspects.claude-code.includes = [ den.aspects.claude-code-cli ];

  den.aspects.claude-code-cli = program {
    # the github plugin expands GITHUB_PERSONAL_ACCESS_TOKEN into its
    # Authorization header. reading the secret at launch keeps it out of
    # other shells, and hosts without the secret start without github mcp.
    pkg =
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
        # khion only because lumi.yaml can only be checked and edited on lumi; add the key there before widening this
        hosts = [ "khion" ];
        sops.secrets."github-mcp-token" = {
          owner = "feltfomo";
          mode = "0400";
        };
        skadi.provision.secrets.github-mcp-token = {
          method = "paste";
          prompt = "GitHub personal access token for the github MCP server";
        };
      }
    ];
  };
}
