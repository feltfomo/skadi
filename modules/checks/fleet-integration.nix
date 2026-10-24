{ inputs, den, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      inherit (pkgs) lib;
      pathOf = key: entry: if builtins.isAttrs entry then entry.${key} else entry;
      contributedPaths = {
        khion = [
          "/var/lib/desktop-commander-mcp"
          "/var/lib/noctalia-greeter"
          "/etc/NetworkManager/system-connections"
          "/var/lib/tailscale"
        ];
        lumi = [ "/etc/NetworkManager/system-connections" ];
      };
      ownedPaths = lib.unique (lib.concatLists (builtins.attrValues contributedPaths));
      results = lib.mapAttrs (
        name: host:
        let
          config = inputs.self.nixosConfigurations.${name}.config;
          homes = config.home-manager.users or { };
          persistence = builtins.attrValues (config.environment.persistence or { });
          directories = lib.concatMap (p: map (pathOf "directory") p.directories) persistence;
          files = lib.concatMap (p: map (pathOf "file") p.files) persistence;
          manifest = config.lexicon.furnish.manifestData or [ ];
          homeResults = lib.mapAttrs (
            user: home:
            let
              account = config.users.users.${user};
              password = config.sops.secrets."${user}-password";
            in
            {
              identity =
                home.home.username == user
                && home.home.homeDirectory == account.home
                && home.home.stateVersion == "25.11";
              passwordRouting = password.neededForUsers && account.hashedPasswordFile == password.path;
              shellContributions =
                user != "feltfomo"
                || (
                  home.programs.fish.enable
                  && home.programs.fzf.enable
                  && home.programs.zoxide.enable
                  && home.programs.git.settings.core.pager == "delta"
                );
              localLlmDisabled =
                !(home.systemd.user.services ? llama-router)
                && !(home.home.sessionVariables ? LLAMA_BASE_URL)
                && !(home.home.file ? ".pi/agent/models.json")
                && builtins.all (
                  package: builtins.match "(local-llm|llama-cpp)(-.*)?" package.name == null
                ) home.home.packages;
            }
          ) homes;
          homeFailures = lib.concatLists (
            lib.mapAttrsToList (
              user: checks:
              map (check: "${name}/${user}/${check}") (
                builtins.filter (check: !checks.${check}) (builtins.attrNames checks)
              )
            ) homeResults
          );
          checks = {
            users = builtins.attrNames homes == builtins.attrNames (host.users or { });
            persistenceContributions =
              lib.sort builtins.lessThan (builtins.filter (p: builtins.elem p ownedPaths) directories)
              == lib.sort builtins.lessThan (contributedPaths.${name} or [ ]);
            homePersistence =
              builtins.all (p: p.users == { }) persistence
              && builtins.all (p: p != "/home" && !lib.hasPrefix "/home/" p) (directories ++ files);
            fileOwnership = builtins.all (
              entry:
              entry.authority.scope != "user"
              || (
                homes ? ${entry.authority.identity}
                && entry.managedRoot == homes.${entry.authority.identity}.home.homeDirectory
                && lib.hasPrefix "${entry.managedRoot}/" entry.filesystemIdentity.destination
              )
            ) manifest;
            grandpaIsolation =
              !(homes ? grandpa)
              || (
                lib.intersectLists [ "wheel" "networkmanager" "docker" ] config.users.users.grandpa.extraGroups
                == [ ]
                && !homes.grandpa.programs.fish.enable
                && !homes.grandpa.programs.zed-editor.enable
                && !(homes.grandpa.systemd.user.services ? bootstrap-repos)
                && builtins.all (entry: entry.authority.identity != "grandpa") manifest
              );
          };
        in
        homeFailures
        ++ map (check: "${name}/${check}") (
          builtins.filter (check: !checks.${check}) (builtins.attrNames checks)
        )
      ) den.hosts.${system};
      failures = lib.concatLists (builtins.attrValues results);
    in
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        fleet-integration =
          assert lib.assertMsg (
            failures == [ ]
          ) "fleet integration failed: ${lib.concatStringsSep ", " failures}";
          pkgs.runCommandLocal "fleet-integration-check" { } ''
            touch "$out"
          '';
      };
    };
}
