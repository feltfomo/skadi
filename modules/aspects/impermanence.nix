{ inputs, ... }:
{
  den.aspects.impermanence.nixos =
    { ... }:
    {
      # provides environment.persistence option
      imports = [ inputs.impermanence.nixosModules.impermanence ];

      # persist and home must be available early in boot
      fileSystems."/persist".neededForBoot = true;
      fileSystems."/home".neededForBoot = true;

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

      # what gets persisted across reboots
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
