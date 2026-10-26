{
  den.aspects.performance.nixos =
    { pkgs, ... }:
    {
      services.scx = {
        enable = true;
        scheduler = "scx_lavd";
      };

      services.ananicy = {
        enable = true;
        package = pkgs.ananicy-cpp;
        rulesProvider = pkgs.ananicy-rules-cachyos_git;
        settings = {
          cgroup_load = false;
          apply_cgroup = false;
        };
      };

      services.irqbalance.enable = true;
    };
}
