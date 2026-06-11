{ inputs, ... }:
{
  den.aspects.hermes.nixos =
    { config, ... }:
    {
      imports = [ inputs.hermes-agent.nixosModules.default ];

      services.hermes-agent = {
        enable = true;
        addToSystemPackages = true;

        # telegram, discord and slack bridges
        extraDependencyGroups = [ "messaging" ];

        # writable ubuntu container so the agent can install its own tools
        container = {
          enable = true;
          backend = "docker";
          hostUsers = [ "feltfomo" ];
          # mount the flake read only so it learns the config without rewriting it
          extraVolumes = [ "/etc/skadi:/etc/skadi:ro" ];
        };

        settings = {
          # groq llama 3.3 70b leads, fast and generous on the free tier
          model = {
            provider = "openai-api";
            default = "llama-3.3-70b-versatile";
            base_url = "https://api.groq.com/openai/v1";
            context_length = 128000;
          };

          # automatic failover stack, tried in order when groq hits a limit or errors
          fallback_providers = [
            {
              provider = "nvidia";
              model = "meta/llama-3.3-70b-instruct";
            }
            {
              provider = "custom";
              model = "gpt-oss-120b";
              base_url = "https://api.cerebras.ai/v1";
              key_env = "CEREBRAS_API_KEY";
            }
            {
              provider = "gemini";
              model = "gemini-flash-latest";
            }
            {
              provider = "openrouter";
              model = "openrouter/free";
            }
          ];

          # pin side tasks to the main groq model so title generation stops hitting gemini
          auxiliary = {
            title_generation.provider = "main";
            triage_specifier.provider = "main";
            approval.provider = "main";
            compression.provider = "main";
          };

          compression.threshold = 0.85;

          # searxng (local) handles search, tavily reads full pages
          web = {
            search_backend = "searxng";
            extract_backend = "tavily";
          };

          toolsets = [ "all" ];
        };

        # nvidia build key and bot tokens, decrypted by sops-nix. provision the
        # value in secrets/secrets.yaml before relying on it (see README).
        environmentFiles = [ config.sops.secrets."hermes-secrets".path ];
      };
    };
}
