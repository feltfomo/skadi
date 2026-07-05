_: {
  den.aspects.installer-tunables.nixos =
    { lib, ... }:
    {
      # installer tunables as data, mirroring provision.nix: skadi-install evals
      # config.skadi.installer (ONE narrow eval, never the whole config) and
      # substitutes these in. every default equals the literal it replaces, so
      # behavior is unchanged -- pure parameterization. included via base.nix so
      # the options land on the TARGET host the installer evals (vm/khion/lumi),
      # NOT the ISO (den.aspects.installer would miss the eval), and stay
      # per-host overridable.
      #
      # NOTE: build-dir + the store-relocation paths (STORE_RW / SWAPFILE) are
      # deliberately NOT here. build-dir is owned by installer.nix and read by
      # the nix-daemon at ISO-build time, so it can't come from a target-host
      # eval; STORE_RW / SWAPFILE are mount-relative literals tied to it.
      # Lifting them would be a dual source of truth + a behavior change.
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
