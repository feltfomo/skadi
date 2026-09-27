{ den, ... }: {
  den.aspects.local-llm = {
    # multi-gig ggufs, re-downloading them every boot isn't an option
    persistence =
      { host, ... }:
      {
        users = builtins.mapAttrs (_: _: {
          directories = [ "Models" ];
        }) host.users;
      };

    homeManager =
      {
        host,
        lib,
        pkgs,
        ...
      }:
      lib.mkIf (host.name == "khion") (
        let
          llamaCpp = pkgs.llama-cpp.override { cudaSupport = true; };
          huggingFace = pkgs.python3.withPackages (ps: [ ps.huggingface-hub ]);
          modelRoot = "%h/Models/local-llm";
          localLlm = pkgs.writeShellApplication {
            name = "local-llm";
            runtimeInputs = [
              huggingFace
              pkgs.coreutils
              pkgs.curl
              pkgs.systemd
            ];
            text = ''
              root="''${LOCAL_LLM_MODEL_ROOT:-$HOME/Models/local-llm}"

              usage() {
                printf '%s\n' \
                  'usage: local-llm fetch <qwen3-coder|bonsai-1bit|bonsai-ternary>' \
                  '       local-llm use <qwen3-coder|bonsai-1bit|bonsai-ternary>' \
                  '       local-llm stop' \
                  '       local-llm status' \
                  '       local-llm restart'
              }

              resolve_model() {
                case "''${1:-}" in
                  qwen3-coder) printf '%s' 'qwen3-coder-30b-a3b' ;;
                  bonsai-1bit) printf '%s' 'bonsai-27b-1bit' ;;
                  bonsai-ternary) printf '%s' 'bonsai-27b-ternary' ;;
                  *)
                    usage >&2
                    exit 2
                    ;;
                esac
              }

              case "''${1:-}" in
                fetch)
                  case "''${2:-}" in
                    qwen3-coder)
                      dest="$root/qwen3-coder-30b-a3b"
                      install -d "$dest"
                      # include glob because unsloth sometimes nests big quants in a subdir
                      hf download unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF \
                        --include '*Q4_K_M*' --local-dir "$dest"
                      ;;
                    bonsai-1bit)
                      dest="$root/bonsai-27b-1bit"
                      install -d "$dest"
                      hf download prism-ml/Bonsai-27B-gguf Bonsai-27B-Q1_0.gguf --local-dir "$dest"
                      ;;
                    bonsai-ternary)
                      dest="$root/bonsai-27b-ternary"
                      install -d "$dest"
                      hf download prism-ml/Ternary-Bonsai-27B-gguf Ternary-Bonsai-27B-Q2_g64.gguf --local-dir "$dest"
                      ;;
                    *)
                      usage >&2
                      exit 2
                      ;;
                  esac
                  systemctl --user restart llama-router.service
                  ;;
                use)
                  model="$(resolve_model "''${2:-}")"
                  curl --fail --silent --show-error \
                    --request POST \
                    http://127.0.0.1:8081/models/load \
                    --header 'Content-Type: application/json' \
                    --data-binary "{\"model\":\"$model\"}"
                  printf '\n'
                  ;;
                stop)
                  for model in qwen3-coder-30b-a3b bonsai-27b-1bit bonsai-27b-ternary; do
                    curl --silent --show-error \
                      --request POST \
                      http://127.0.0.1:8081/models/unload \
                      --header 'Content-Type: application/json' \
                      --data-binary "{\"model\":\"$model\"}" >/dev/null || true
                  done
                  ;;
                status)
                  systemctl --user --no-pager status llama-router.service
                  printf '\n'
                  curl --fail --silent --show-error http://127.0.0.1:8081/health
                  printf '\n'
                  curl --fail --silent --show-error http://127.0.0.1:8081/models
                  printf '\n'
                  ;;
                restart)
                  systemctl --user restart llama-router.service
                  ;;
                *)
                  usage >&2
                  exit 2
                  ;;
              esac
            '';
          };
        in
        {
          home.packages = [
            llamaCpp
            localLlm
          ];

          home.sessionVariables.LLAMA_BASE_URL = "http://127.0.0.1:8081";

          # pi discovers nothing on its own, every local model has to be listed here
          home.file.".pi/agent/models.json".text = builtins.toJSON {
            providers.llama-router = {
              baseUrl = "http://127.0.0.1:8081/v1";
              api = "openai-completions";
              apiKey = "none";
              models = [
                { id = "qwen3-coder-30b-a3b"; }
                { id = "bonsai-27b-1bit"; }
                { id = "bonsai-27b-ternary"; }
              ];
            };
          };

          systemd.user.services.llama-router = {
            Unit.Description = "Local GGUF model router";
            Service = {
              ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p ${modelRoot}";
              # cpu-moe puts every expert in ram and leaves attention plus kv cache on the 4060.
              # a numeric --n-cpu-moe aborts llama.cpp's auto-fit and ooms an 8gb card on a 48 layer moe.
              # q8 kv cache halves vram per token, which is what buys the 64k context on an 8gb card
              ExecStart = "${llamaCpp}/bin/llama-server --models-dir ${modelRoot} --models-max 1 --no-models-autoload --jinja --reasoning-budget 1024 --cpu-moe -ctk q8_0 -ctv q8_0 --host 127.0.0.1 --port 8081 -c 65536";
              Restart = "on-failure";
              RestartSec = 5;
            };
            Install.WantedBy = [ "default.target" ];
          };
        }
      );
  };

  den.aspects.feltfomo.includes = [ den.aspects.local-llm ];
}
