{
  den.aspects.installer-tunables.nixos =
    { lib, ... }:
    {
      # skadi-install reads these values from the target host configuration.
      # defaults match the literals they replace and remain overridable per host.
      # build-dir, STORE_RW, and SWAPFILE stay with installer-time store setup.
      options.skadi.installer = {
        swapSizeGiB = lib.mkOption {
          type = lib.types.ints.positive;
          default = 8;
          description = "Size (GiB) of the temporary build swapfile added on low-RAM hosts.";
        };
        lowRamThresholdGiB = lib.mkOption {
          type = lib.types.ints.positive;
          default = 16;
          description = "Add the build swapfile when total RAM is below this many GiB.";
        };
        minFreeGiB = lib.mkOption {
          type = lib.types.ints.positive;
          default = 5;
          description = "nix --min-free (GiB): GC unneeded store paths mid-build below this.";
        };
        maxFreeGiB = lib.mkOption {
          type = lib.types.ints.positive;
          default = 10;
          description = "nix --max-free (GiB): mid-build GC target ceiling.";
        };
        diskFloorGiB = lib.mkOption {
          type = lib.types.ints.positive;
          default = 30;
          description = "Hard floor (GiB) of free space on /mnt; install aborts below this.";
        };
        diskWarnGiB = lib.mkOption {
          type = lib.types.ints.positive;
          default = 80;
          description = "Warn below this (GiB): ok for a cached install, tight for a cold from-source build.";
        };
        maxJobs = lib.mkOption {
          type = lib.types.ints.positive;
          default = 1;
          description = "nix --max-jobs: parallel derivations during the closure build.";
        };
        cores = lib.mkOption {
          type = lib.types.ints.unsigned;
          default = 0;
          description = "nix --cores per build (0 = all available cores).";
        };
      };
    };
}
