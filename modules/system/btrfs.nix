{
  # every host sits on one btrfs filesystem. btrfs hands the whole device out in data and metadata
  # chunks and never gives a half-empty data chunk back on its own, so a workload of millions of
  # small files fills metadata while data chunks still hold free space, and every write then fails
  # with ENOSPC.
  den.aspects.btrfs.nixos =
    { pkgs, ... }:
    {
      # dynamic reclaim compacts data chunks with low usage, more eagerly as unallocated space runs
      # out, and periodic reclaim checks for them in the background rather than only on frees.
      systemd.tmpfiles.rules = [
        "w /sys/fs/btrfs/*/allocation/data/dynamic_reclaim - - - - 1"
        "w /sys/fs/btrfs/*/allocation/data/periodic_reclaim - - - - 1"
      ];

      # a backstop for reclaim: a weekly balance of nearly empty data chunks, at idle priority.
      systemd.services.btrfs-balance = {
        description = "Return nearly empty btrfs data chunks to unallocated space";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.btrfs-progs}/bin/btrfs balance start -dusage=10 /";
          Nice = 19;
          IOSchedulingClass = "idle";
        };
      };
      systemd.timers.btrfs-balance = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "weekly";
          Persistent = true;
          RandomizedDelaySec = "1h";
        };
      };
    };
}
