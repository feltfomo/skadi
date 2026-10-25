# DO-NOT-EDIT. This file was auto-generated using github:vic/flake-file.
# Use `nix run .#write-flake` to regenerate it.
{
  description = "skadi";

  outputs = inputs: import ./outputs.nix inputs;

  nixConfig = {
    extra-substituters = [
      "https://noctalia.cachix.org"
      "https://walker.cachix.org"
      "https://walker-git.cachix.org"
      "https://hyprland.cachix.org"
    ];
    extra-trusted-public-keys = [
      "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
      "walker-git.cachix.org-1:vmC0ocfPWh0S/vRAQGtChuiZBTAe4wiKDeyyXM0/7pM="
      "walker.cachix.org-1:fG8q+uAaMqhsMxWjwvk0IMb4mFPFLqHjuvfwQxE4oJM="
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
    ];
  };

  inputs = {
    ai-usagebar = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:akitaonrails/ai-usagebar";
    };
    caelestia = {
      inputs = {
        nixpkgs.follows = "nixpkgs";
        quickshell.follows = "quickshell";
      };
      url = "github:caelestia-dots/shell";
    };
    chaotic.url = "github:chaotic-cx/nyx/nyxpkgs-unstable";
    den.url = "github:denful/den/v0.19.0";
    disko = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:nix-community/disko";
    };
    dms = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:AvengeMedia/DankMaterialShell";
    };
    elephant = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:abenz1267/elephant";
    };
    flake-file.url = "github:denful/flake-file/v0.3.0";
    flake-parts.url = "github:hercules-ci/flake-parts";
    gloview = {
      inputs.hyprland.follows = "hyprland";
      url = "github:fedsfarm/gloview";
    };
    home-manager = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:nix-community/home-manager";
    };
    hyprland.url = "github:hyprwm/Hyprland?ref=v0.56.2";
    illogical-impulse.url = "github:feltfomo/illogical-impulse-shell-nix";
    impermanence.url = "github:nix-community/impermanence";
    import-tree.url = "github:vic/import-tree";
    lexicon = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:feltfomo/lexicon";
    };
    llm-agents = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:numtide/llm-agents.nix";
    };
    mango = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:mangowm/mango";
    };
    millennium = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:SteamClientHomebrew/Millennium/f7a356f6789bc7d23f44bfbcdd95c71f0385cc1a?dir=packages/nix";
    };
    niri = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:epireyn/niri-flake";
    };
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-logseq.url = "github:NixOS/nixpkgs/master";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-26.05";
    no-ai-slop = {
      flake = false;
      url = "github:petergyang/no-ai-slop/000650b156983f5159695b441477f4e63b25dc85";
    };
    noctalia = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:noctalia-dev/noctalia";
    };
    noctalia-community-plugins = {
      flake = false;
      url = "github:noctalia-dev/community-plugins/e9dec7443b8a70ab606dc72669fb122a9d668bce";
    };
    noctalia-greeter = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:noctalia-dev/noctalia-greeter";
    };
    pi-extensions = {
      inputs = {
        home-manager.follows = "home-manager";
        nixpkgs.follows = "nixpkgs";
      };
      url = "github:feltfomo/pi-extensions";
    };
    quickshell = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:quickshell-mirror/quickshell";
    };
    serpantinum = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:ilyamiro/serpantinum/9861a84d8a798dfd520102912db507773dc18971";
    };
    sops-nix = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:Mic92/sops-nix";
    };
    spicetify-lucid = {
      flake = false;
      url = "gitlab:sanoojes/spicetify-lucid?ref=main";
    };
    spicetify-nix = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:Gerg-L/spicetify-nix";
    };
    steam-aika = {
      flake = false;
      url = "github:hatewxb/Aika/d7722137658a9f89ca8af7dfc563620b3c03a7fe";
    };
    t3-code-nix.url = "github:LisaScheers/t3-code-nix";
    treefmt-nix = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:numtide/treefmt-nix";
    };
    walker = {
      inputs = {
        elephant.follows = "elephant";
        nixpkgs.follows = "nixpkgs";
      };
      url = "github:abenz1267/walker";
    };
    zen-browser = {
      inputs = {
        home-manager.follows = "home-manager";
        nixpkgs.follows = "nixpkgs";
      };
      url = "github:0xc000022070/zen-browser-flake";
    };
  };

}
