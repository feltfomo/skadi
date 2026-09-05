{ inputs, furnishRuntime, ... }:
{
  # impermanence declares no nixpkgs input, so there is nothing to follow.
  flake-file.inputs.impermanence.url = "github:nix-community/impermanence";

  den.aspects.impermanence.nixos =
    {
      config,
      lib,
      persistence,
      ...
    }:
    let
      mergePaths = entries: {
        directories = lib.concatMap (entry: entry.directories or [ ]) entries;
        files = lib.concatMap (entry: entry.files or [ ]) entries;
      };
      systemPersistence = mergePaths persistence;
      userNames = lib.unique (lib.concatMap (entry: lib.attrNames (entry.users or { })) persistence);
      userPersistence = lib.genAttrs userNames (
        name: mergePaths (map (entry: (entry.users or { }).${name} or { }) persistence)
      );
    in
    {
      # this aspect owns the furnish import instead of assuming another aspect
      # pulled the runtime in first. hosts without furnish stay inert because
      # enable defaults to false.
      imports = [
        inputs.impermanence.nixosModules.impermanence
        furnishRuntime
      ];

      # persist and home must be available early in boot
      fileSystems."/persist".neededForBoot = true;
      fileSystems."/home".neededForBoot = true;

      # the ledger is the only thing between a repair decision and a blanket
      # refusal. @ is replaced from @blank on every boot, so the ledger lives on
      # /persist directly rather than behind an environment.persistence bind mount.
      lexicon.furnish.state = {
        path = "/persist/var/lib/furnish";
        durability = "durable";
        requiresMountsFor = [ "/persist" ];
      };

      assertions =
        let
          cfg = config.lexicon.furnish;
          inherit (cfg) state;
          declared = lib.attrNames config.fileSystems;
          encloses =
            mount: state.path == mount || lib.hasPrefix (lib.removeSuffix "/" mount + "/") state.path;
          enclosing = lib.foldl' (
            best: mount: if builtins.stringLength mount > builtins.stringLength best then mount else best
          ) "/" (lib.filter encloses declared);
        in
        # a host without furnish reconciles nothing and reads no ledger, so it
        # owes no durability proof.
        lib.optionals cfg.enable [
          {
            # a durability claim is worth exactly the mount behind it. the
            # filesystem carrying the state must be declared before its readers.
            assertion =
              state.durability != "durable"
              || (config.fileSystems ? ${enclosing} && config.fileSystems.${enclosing}.neededForBoot);
            message = "lexicon.furnish.state.durability is \"durable\" but the filesystem carrying ${state.path} (${enclosing}) is not declared with neededForBoot";
          }
        ];

      # rollback btrfs root to blank snapshot on every boot
      boot.initrd.systemd.services.rollback = {
        description = "Rollback Btrfs root subvolume to blank";
        wantedBy = [ "initrd.target" ];
        after = [ "systemd-cryptsetup@cryptroot.service" ];
        before = [ "sysroot.mount" ];
        unitConfig.DefaultDependencies = "no";
        serviceConfig.Type = "oneshot";
        script = ''
          mkdir -p /mnt
          mount -t btrfs /dev/mapper/cryptroot /mnt
          if [ -e /mnt/@ ]; then
            mkdir -p /mnt/@old
            timestamp=$(date --date="@$(stat -c %Y /mnt/@)" "+%Y-%m-%d_%H:%M:%S")
            mv /mnt/@ "/mnt/@old/$timestamp"
          fi
          echo "Creating fresh @ subvolume from @blank..."
          btrfs subvolume snapshot /mnt/@blank /mnt/@

          old_roots=(/mnt/@old/*)
          if [ -e "''${old_roots[0]}" ]; then
            while [ "''${#old_roots[@]}" -gt 5 ]; do
              oldest="''${old_roots[0]}"
              echo "Deleting expired root $oldest..."
              if ! btrfs subvolume delete -R "$oldest"; then
                echo "Failed to delete $oldest; leaving remaining roots in place" >&2
                break
              fi
              old_roots=("''${old_roots[@]:1}")
            done
          fi
          umount /mnt
        '';
      };

      environment.persistence."/persist" = {
        hideMounts = true;
        directories = [
          "/etc/nixos"
          "/etc/skadi"
          "/var/log"
          "/var/lib/bluetooth"
          "/var/lib/systemd/coredump"
          "/var/lib/nixos"
        ]
        ++ systemPersistence.directories;
        files = [
          "/etc/machine-id"
          "/etc/ssh/ssh_host_ed25519_key"
          "/etc/ssh/ssh_host_ed25519_key.pub"
          "/etc/ssh/ssh_host_rsa_key"
          "/etc/ssh/ssh_host_rsa_key.pub"
        ]
        ++ systemPersistence.files;
        users = userPersistence;
      };
    };
}
