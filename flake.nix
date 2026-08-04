{
  description = "skadi";

  # binary caches
  nixConfig = {
    extra-substituters = [
      "https://hyprland.cachix.org"
      "https://walker.cachix.org"
      "https://walker-git.cachix.org"
      "https://noctalia.cachix.org"
    ];
    extra-trusted-public-keys = [
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
      "walker.cachix.org-1:fG8q+uAaMqhsMxWjwvk0IMb4mFPFLqHjuvfwQxE4oJM="
      "walker-git.cachix.org-1:vmC0ocfPWh0S/vRAQGtChuiZBTAe4wiKDeyyXM0/7pM="
      "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
    ];
  };

  # flake inputs
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # temporary logseq's buildPhase hangs on nixos-unstable until the yauzl fix
    # (nixpkgs #536292) reaches that branch; pull logseq from master meanwhile.
    # drop this input and revert feltfomo.nix once nixos-unstable has the fix.
    nixpkgs-logseq.url = "github:NixOS/nixpkgs/master";
    # stable pin for the reinstall ISO only (nixosConfigurations.installer),
    # independent of the unstable channel the fleet tracks so the installer
    # stays reproducible while the main config churns.
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-26.05";
    hyprland = {
      url = "github:hyprwm/Hyprland";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    mango = {
      url = "github:mangowm/mango";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    niri = {
      url = "github:sodiboo/niri-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    dms = {
      url = "github:AvengeMedia/DankMaterialShell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    caelestia = {
      url = "github:caelestia-dots/shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    elephant = {
      url = "github:abenz1267/elephant";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    import-tree.url = "github:vic/import-tree";
    flake-parts.url = "github:hercules-ci/flake-parts";
    # impermanence only ships nixosModules and declares no nixpkgs input,
    # so there is no nixpkgs for it to follow.
    impermanence.url = "github:nix-community/impermanence";
    spicetify-nix = {
      url = "github:Gerg-L/spicetify-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    spicetify-lucid = {
      url = "gitlab:sanoojes/spicetify-lucid?ref=main";
      flake = false;
    };
    den.url = "github:denful/den/v0.17.0";
    hermes-agent = {
      # pinned to a tagged release instead of the moving main branch
      url = "github:NousResearch/hermes-agent/v2026.6.5";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    notion-sync = {
      url = "github:feltfomo/notion-sync";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    noctalia = {
      url = "github:noctalia-dev/noctalia";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    noctalia-greeter = {
      url = "github:noctalia-dev/noctalia-greeter";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    lix = {
      # the lix head revision is pinned in flake.lock
      url = "https://git.lix.systems/lix-project/lix/archive/main.tar.gz";
      flake = false;
    };
    lix-module = {
      url = "https://git.lix.systems/lix-project/nixos-module/archive/main.tar.gz";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.lix.follows = "lix";
    };
    walker = {
      url = "github:abenz1267/walker";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.elephant.follows = "elephant";
    };
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        home-manager.follows = "home-manager";
      };
    };
  };

  # den drives the fleet, flake-parts kept for perSystem devshells
  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } (
      { lib, den, ... }:
      let
        # the ownerships surface bound to the fleet roster, read once through
        # the one sanctioned den touch-site so program.nix (and any future
        # aspect) reach it the same way resolve/resolveSystem already do.
        denApi = import ./modules/_lib/den.nix { inherit den lib; };
        # whole-fleet roster over every system in den.hosts, not the flake-parts
        # systems list below (which only scopes perSystem devshells).
        inherit (denApi) roster;
        ownershipsSurface = import ./modules/_lib/ownerships/surface.nix { inherit lib; };
        resolve = ownershipsSurface.mkResolve roster;
        # host-only sibling for system/nixos slices that own by host with no
        # user in scope (hyprland's compositor). a distinct door from mkResolve
        # so the user-scope contract stays byte-identical.
        resolveSystem = ownershipsSurface.mkResolveSystem roster;
      in
      {
        imports = [ (inputs.import-tree ./modules) ];
        systems = [ "x86_64-linux" ];
        # rootPath, program, resolve, resolveSystem ride the same _module.args
        # seam so every aspect gets them like lib. they stay pure libs -- no
        # den plumbing on this path.
        _module.args = {
          rootPath = ./.;
          inherit resolve resolveSystem;
          program = import ./modules/_lib/program.nix {
            inherit lib resolve resolveSystem;
            inherit (denApi) filePrincipals hostUserNames;
          };
        };
      }
    );
}
