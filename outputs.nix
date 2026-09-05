inputs:
inputs.flake-parts.lib.mkFlake { inherit inputs; } (
  { den, ... }:
  let
    # lexicon binds its own framework dependencies behind the public api.
    ownerships = inputs.lexicon.lib.ownerships { };
    # the ownerships surface bound to the fleet roster, read once through
    # the one sanctioned den touch-site so program.nix and future aspects
    # reach it through the same resolve doors.
    denApi = inputs.lexicon.lib.den { inherit den; };
    # whole-fleet roster over every system in den.hosts, not the flake-parts
    # systems list below (which only scopes perSystem devshells).
    inherit (denApi) roster;
    resolve = ownerships.mkResolve roster;
    # host-only sibling for system/nixos slices that own by host with no
    # user in scope (hyprland's compositor). a distinct door from mkResolve
    # so the user-scope contract stays byte-identical.
    resolveSystem = ownerships.mkResolveSystem roster;
    # prepared form used by program aspects to hoist the ctx-independent
    # half of the pipeline out of the per-user slices.
    resolvePrepared = ownerships.mkResolvePrepared roster;
  in
  {
    imports = [ (inputs.import-tree ./modules) ];
    systems = [ "x86_64-linux" ];
    # rootPath, program, resolve, resolveSystem ride the same _module.args
    # seam so every aspect gets them like lib. they stay pure libs -- no
    # den plumbing on this path.
    _module.args = {
      rootPath = ./.;
      inherit
        resolve
        resolveSystem
        resolvePrepared
        ownerships
        roster
        ;
      program = inputs.lexicon.lib.program {
        inherit
          resolve
          resolveSystem
          resolvePrepared
          ;
        inherit (denApi) filePrincipals hostUserNames;
      };
      # applied once here so an aspect that owns a furnish option imports the
      # runtime module instead of re-deriving it.
      furnishRuntime = inputs.lexicon.lib.furnishRuntime { };
      inherit denApi;
    };
  }
)
