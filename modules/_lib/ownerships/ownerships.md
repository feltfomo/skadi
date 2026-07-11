Aspects register config to whoever owns it, right on the unit itself. No `{ host, user }:` wrapper, no `let for = scoped.for ...`, no `let … in` threading between blocks. A unit self-labels with `hosts` / `users` / `exceptHosts` / `exceptUsers` / `when`; leave all of that off and the unit is globally owned. One `resolve` (or `resolveSystem`) composes the tree, checks it against the roster, keeps what applies to this build, and merges the survivors.

The engine underneath (`engine.nix`, `axes.nix`, `merge.nix`) is axis-agnostic and never names `host` or `user` on its own — `axes.nix` is the one file that registers them. Everything below is how aspects actually use the surface (`surface.nix`) that sits on top.

## The authoring surface

A unit is a plain attrset. Anything on it that isn't a claim key is config; `children` nests. The claim keys:

- `hosts` / `exceptHosts` — own by this set of hosts, or by everyone except this set. Can't set both on the same unit — nest an `exceptHosts` child under a `hosts` parent instead ("own by A except B").
- `users` / `exceptUsers` — same shape, on users.
- `when` — a predicate function of the build context, for anything a name-list can't express.
- Untagged (none of the above) = globally owned. That's the default, not a special case.

One documented limitation: a unit can't also carry a config value whose first path segment collides with a claim key. In practice that's only `users.*` — nothing migrated onto this surface owns NixOS's `users.*` yet, so it hasn't needed an escape hatch.

Two doors, both bound to a roster once (`mkResolve roster` / `mkResolveSystem roster`) and handed to aspects as module args:

- **`resolve`** — user scope. The build ctx carries both `host` and `user`; a unit here can narrow on `users`/`exceptUsers`. Use it for anything genuinely per-user: home-manager or hjem content.
- **`resolveSystem`** — host-only / system scope. The build ctx carries `host`, no `user`. Use it for nixos-only slices where there's no single user to narrow to — a compositor, a system package, a systemd service. Narrowing on `users`/`exceptUsers` inside a `resolveSystem` tree is a hard author-time error, not a resolve-time surprise: `ownerships: a system-scope (host-only) unit sets 'users' = [...] -- a host-only slice binds no user, so it cannot narrow on users. drop the user claim or resolve this unit at user scope.`

None of the shipped aspects call `mkResolve`/`mkResolveSystem` by name — they get `resolve`/`resolveSystem`/`program` handed in as module args, already bound to the fleet roster. `program` (`_lib/program.nix`) is a level up from this doc: a spec DSL for packages/files/templates that forwards the same claim keys (`hosts`, `users`, …) into the surface underneath. This doc covers the surface itself, not `program`'s spec shape.

**Fully untagged** — `kitty.nix` claims nothing, so it's globally owned and needs no wrapper at all:

```nix
den.aspects.kitty = program {
  pkg = pkgs: pkgs.kitty;
  files = [
    {
      dest = ".config/kitty/kitty.conf";
      src = "${rootPath}/configs/kitty/kitty.conf";
    }
  ];
  templates = [
    {
      name = "kitty.conf";
      templateFile = "${rootPath}/configs/kitty/themes/skadi.conf";
    }
  ];
};
```

**Whole-aspect host-only** — `audio.nix` claims two hosts and nothing else:

```nix
{ resolveSystem, ... }:
{
  den.aspects.audio =
    { host, ... }:
    {
      nixos =
        { pkgs, ... }:
        resolveSystem [
          {
            hosts = [ "khion" "lumi" ];
            environment.systemPackages = [ pkgs.pavucontrol ];
          }
        ] { inherit host; };
    };
}
```

**Host-only compositor gate, alongside home slices from `program`** — `hyprland.nix`'s `nixos` output resolves through `resolveSystem` (no user in scope at this slice); its `homeManager`/`hjem` output comes from `program`, which is where per-user narrowing would live if this aspect needed it:

```nix
nixos =
  { pkgs, ... }:
  resolveSystem
    [
      {
        hosts = [ "khion" "lumi" ];
        programs.hyprland = {
          enable = true;
          package = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
          portalPackage =
            inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland;
        };
        services.flatpak.enable = true;
      }
    ]
    { inherit host; };
```

**Untagged-global aspect with one host-narrowed field** — `notion-sync.nix` splits into two units: everything global except `keepWarm`, which only khion gets (the full `settings.mapping` list is elided below — see the live file):

```nix
{ inputs, resolveSystem, ... }:
{
  den.aspects.notion-sync =
    { host, ... }:
    {
      nixos =
        { config, ... }:
        resolveSystem [
          {
            imports = [ inputs.notion-sync.nixosModules.notion-sync ];
            sops.secrets."notion-token" = { owner = "feltfomo"; mode = "0400"; };
            environment.systemPackages = [ config.services.notion-sync.package ];
            services.notion-sync = {
              enable = true;
              environmentFile = config.sops.secrets."notion-token".path;
              logLevel = "info";
              settings.webhook = { enabled = true; port = 8080; };
              settings.mapping = [ /* ... */ ];
            };
          }
          {
            # the unit above stays untagged (global); this one field is host-narrowed.
            hosts = [ "khion" ];
            services.notion-sync.keepWarm = {
              enable = true;
              url = "https://khion.tail4f0c8e.ts.net/notion-webhook";
              forcePublicPath = true;
            };
          }
        ] { inherit host; };
    };
}
```

## The three outcomes

Only two things ever raise an error. Everything else that doesn't match this build just silently isn't there.

**Inactive — silent.** `audio.nix`'s own comment says it straight: `pavucontrol` is claimed by `khion`/`lumi`, and `resolveSystem` drops the unit on any other host. The installer-test VM and `generic` also pull `audio`, and both collapse to `{}` for it — no error, no pavucontrol, nothing to clean up.

**Impossible — loud error.** A claim can only narrow its parent; a disjoint nest is a contradiction, not a silent no-op. Nesting a `lumi`-only child under a `khion`-only parent claims an entity that can never exist for that unit (illustrative, not shipped):

```nix
{
  hosts = [ "khion" ];
  children = [
    {
      hosts = [ "lumi" ]; # narrows against "khion" -> empty set, not "lumi"
      programs.foo.enable = true;
    }
  ];
}
```

`narrowClaim` intersects `include ["khion"]` with `include ["lumi"]` and gets `include []` — unsatisfiable against any roster, so `satisfiableCheck` throws before `select` ever runs. The same class of error covers a typo'd name and a host/user pair that never co-exist (`mkMembershipCheck`).

**Conflict — loud error.** Two real co-owners, both satisfiable, setting the same scalar to different values. Two sibling units both claimed by `khion` can't disagree on whether `keepWarm` is enabled (illustrative, not shipped):

```nix
[
  { hosts = [ "khion" ]; services.notion-sync.keepWarm.enable = true; }
  { hosts = [ "khion" ]; services.notion-sync.keepWarm.enable = false; }
]
```

Both survive `select`; `merge` recurses into the shared attrset path down to the scalar, finds `true != false`, and throws `strictScalar`'s structured message instead of picking a winner. Attrsets merge (union of keys, recursing into shared ones) and lists concatenate in order by default — only a genuine scalar clash between real co-owners is a conflict.

## The den boundary, and running without den

A roster is exactly `{ hosts; users; membership; usersWithUnknownMembership }` — host and user name lists, `membership` as host → `[user]`, and `usersWithUnknownMembership` for a standalone user that never named its hosts. `resolve.nix`'s `engineArgsFor` builds the axis registry and the membership check from this shape; neither the engine nor the axes know or care where it came from.

Two backends produce it:

- **den** — the adapter in `_lib/den.nix` (the one file allowed to touch den internals) reads `den.hosts.<system>.<host>.users` and shapes it into a roster. This is what every aspect in this repo is bound against.
- **Standalone, no den** — `roster.nix`'s `define.*` builds the same shape with no den present:

```nix
let
  inherit (import ./roster.nix { inherit lib; }) define toRoster;
in
toRoster [
  (define.host "khion")
  (define.host "lumi")
  (define.user "feltfomo" { hosts = [ "khion" "lumi" ]; })
]
```

A user with `hosts = null` (the default) means "unknown", and the membership check lets it through anywhere (`usersWithUnknownMembership`); an explicit `hosts = []` means "known to live nowhere", and stays a real membership failure. Feed either roster into `resolveWith`/`mkResolve` and the claim vocabulary — `hosts`, `users`, `exceptHosts`, `exceptUsers`, `when` — doesn't change at all.

