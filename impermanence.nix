{ ... }:
{
  fileSystems."/persist".neededForBoot = true;
  fileSystems."/home".neededForBoot = true;

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
      "/var/log"
      "/var/lib/bluetooth"
      "/var/lib/systemd/coredump"
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
    users.feltfomo = {
      directories = [
        "Downloads"
        "Documents"
        "Pictures"
        "Videos"
        "Music"
        ".config"
        ".local"
        ".ssh"
      ];
    };
  };
}
