{ inputs, furnishRuntime, ... }:
{
  den.aspects.impermanence.nixos =
    { config, lib, ... }:
    {
      # This aspect names a furnish option, so it owns the import rather than
      # assuming some other aspect pulled the runtime in first. Hosts that take
      # impermanence without furnish stay inert: enable defaults false, so this
      # only brings the option namespace into scope.
      imports = [
        inputs.impermanence.nixosModules.impermanence
        furnishRuntime
      ];

      # persist and home must be available early in boot
      fileSystems."/persist".neededForBoot = true;
      fileSystems."/home".neededForBoot = true;

      # The ledger is the only thing standing between a repair decision and a
      # blanket refusal, and @ is snapshotted away from @blank on every boot, so
      # it has to live on the persisted subvolume. It is written to /persist
      # directly rather than being listed in environment.persistence: that list
      # bind-mounts paths back into the wiped root, which is a mount ordering
      # dependency the reconcile unit does not need to take on.
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
        # A host that imports this aspect without enabling furnish reconciles
        # nothing and reads no ledger, so it owes no durability proof.
        lib.optionals cfg.enable [
          {
            # A durability claim is worth exactly the mount behind it. Asserting
            # the path spells /persist would prove nothing; asserting that the
            # filesystem actually carrying it is declared and available before
            # the units that read it is the claim itself.
            assertion =
              state.durability != "durable"
              || (config.fileSystems ? ${enclosing} && config.fileSystems.${enclosing}.neededForBoot);
            message = "lexicon.furnish.state.durability is \"durable\" but the filesystem carrying ${state.path} (${enclosing}) is not declared with neededForBoot";
          }
        ];

      # rollback btrfs root to blank snapshot on every boot
      boot.initrd.systemd.services.rollback = {
        description = "Rollback BTRFS root subvolume to blank";
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
          # tailscale node identity + funnel/serve config -- without this, khion
          # re-registers as a brand-new node every boot (khion-1, khion-2, ...)
          # and loses the funnel, forcing a fresh `tailscale up` + funnel setup
          "/var/lib/tailscale"
          "/etc/NetworkManager/system-connections"
          "/var/lib/nixos"
          # synced greeter appearance + remembered session/scheme (noctalia-greeter)
          "/var/lib/noctalia-greeter"
        ];
        files = [
          "/etc/machine-id"
          "/etc/ssh/ssh_host_ed25519_key"
          "/etc/ssh/ssh_host_ed25519_key.pub"
          "/etc/ssh/ssh_host_rsa_key"
          "/etc/ssh/ssh_host_rsa_key.pub"
        ];
      };
    };
}
