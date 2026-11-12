# read-only GitHub token. nix fetches private `github:` inputs as tarballs, which need a token, not
# an ssh key. claude code's github plugin reads the same secret.
{ lib, ... }:
let
  secret = "github-token";
in
{
  den.aspects.github-token.nixos =
    { config, host, ... }:
    lib.mkIf
      (builtins.elem host.name [
        "khion"
        "lumi"
      ])
      {
        sops.secrets.${secret} = {
          owner = "feltfomo";
          mode = "0400";
        };
        skadi.provision.secrets.${secret} = {
          method = "paste";
          prompt = "read-only GitHub token (Contents) for private repositories";
        };
        # owned by feltfomo so nix run as the user can read it too.
        sops.templates."nix-access-tokens" = {
          owner = "feltfomo";
          mode = "0400";
          content = ''
            access-tokens = github.com=${config.sops.placeholder.${secret}}
          '';
        };
        # `!include` skips a missing file, so nix works before sops renders it.
        nix.extraOptions = ''
          !include ${config.sops.templates."nix-access-tokens".path}
        '';
      };
}
