# Using Ownerships

Ownerships selects and merges configuration according to host, user, and predicate claims. It works as a standalone Nix library: Den and Program are integrations built around it, not runtime requirements.

This guide starts with standalone use, including ordinary NixOS and Home Manager configurations that do not use Den.

## Ways to use Ownerships

1. **Pure Nix:** construct a roster, create a resolver, and resolve ordinary values.
2. **NixOS or Home Manager without Den:** return resolved configuration from a normal module.
3. **skadi integration:** use Program or Den-provided resolvers when those layers are already available.

All three paths use the same claims and selection machinery.

---

## Standalone quick start

A standalone evaluation needs `nixpkgs.lib`, the Ownerships library, a roster, units, and a concrete context:

```nix
let
  pkgs = import <nixpkgs> { };
  lib = pkgs.lib;

  ownerships = import ./modules/_lib/ownerships {
    inherit lib;
  };

  roster = ownerships.toRoster [
    (ownerships.define.host "khion" {
      system = "x86_64-linux";
    })

    (ownerships.define.user "feltfomo" {
      hosts = [ "khion" ];
    })
  ];

  resolve = ownerships.mkResolve roster;
in
resolve [
  { shared = true; }
  {
    hosts = [ "khion" ];
    desktop = true;
  }
  {
    users = [ "feltfomo" ];
    editor = "helix";
  }
] {
  host = {
    name = "khion";
    system = "x86_64-linux";
  };
  user = {
    name = "feltfomo";
  };
}
```

The result is an ordinary merged value:

```nix
{
  shared = true;
  desktop = true;
  editor = "helix";
}
```

Nothing in this example depends on Den, aspects, NixOS modules, or Home Manager.

## What standalone callers provide

Den normally wires several values together. Standalone callers make them explicit:

- an imported Ownerships facade;
- a roster containing every host and user named by claims;
- a user-scope or system-scope resolver;
- a list of units;
- the concrete host and, for user scope, user context.

Ownerships does not discover machines or accounts from NixOS. The roster is the finite ownership model against which claims are validated.

---

## Build a standalone roster

### Hosts

```nix
ownerships.define.host "khion" {
  system = "x86_64-linux";
}
```

This host has canonical identity:

```text
x86_64-linux/khion
```

Both the canonical ID and the unique alias `khion` may be used in claims.

The compact form is also valid:

```nix
ownerships.define.host "khion"
```

Without an explicit system, its canonical ID is `standalone/khion`. Prefer an explicit system for real NixOS hosts.

### Users and membership

```nix
ownerships.define.user "feltfomo" {
  hosts = [ "khion" ];
}
```

The host membership defines valid host/user pairs. A host and user can each exist in the roster while a particular pair is still incompatible.

### Assemble the roster

```nix
roster = ownerships.toRoster [
  (ownerships.define.host "khion" {
    system = "x86_64-linux";
  })
  (ownerships.define.host "lumi" {
    system = "aarch64-linux";
  })
  (ownerships.define.user "feltfomo" {
    hosts = [ "khion" "lumi" ];
  })
  (ownerships.define.user "guest" {
    hosts = [ "khion" ];
  })
];
```

`toRoster` uses the built-in host and user descriptors. `mkRoster` is the lower-level constructor for custom descriptor sets.

### Aliases

A unique bare host name resolves to its canonical member. If multiple systems define the same bare name, the alias is ambiguous and claims must use canonical IDs:

```nix
hosts = [ "x86_64-linux/build" ];
```

Unknown and ambiguous members are declaration errors, not inactive claims.

---

## Contexts and scopes

### User scope

`mkResolve` receives both host and user entities:

```nix
{
  host = {
    name = "khion";
    system = "x86_64-linux";
  };
  user = {
    name = "feltfomo";
  };
}
```

### System scope

`mkResolveSystem` receives only a host:

```nix
{
  host = {
    name = "khion";
    system = "x86_64-linux";
  };
}
```

System scope recursively rejects `users` and `exceptUsers`. Use it for NixOS configuration that does not represent one user.

### Ordinary and strict doors

Ordinary resolvers validate authored claims and demand only context axes selected claims need. This preserves laziness for global and host-only units.

Strict resolvers also require the supplied context itself to be known and relation-compatible with the roster:

```nix
resolveStrict = ownerships.mkResolveStrict roster;
resolveSystemStrict = ownerships.mkResolveSystemStrict roster;
```

Use strict mode at standalone entry points when every supplied entity must be roster-valid even if all selected units are global.

---

## Reusable standalone setup

A small project can centralize its roster and resolver doors without introducing Den:

```text
configuration/
├── ownerships.nix
├── units/
│   ├── home.nix
│   └── system.nix
├── home.nix
└── configuration.nix
```

### `ownerships.nix`

```nix
{ lib }:
let
  ownerships = import ../modules/_lib/ownerships {
    inherit lib;
  };

  roster = ownerships.toRoster [
    (ownerships.define.host "khion" {
      system = "x86_64-linux";
    })
    (ownerships.define.user "feltfomo" {
      hosts = [ "khion" ];
    })
  ];
in
{
  inherit ownerships roster;

  resolve = ownerships.mkResolve roster;
  resolveSystem = ownerships.mkResolveSystem roster;
  resolveStrict = ownerships.mkResolveStrict roster;
  resolveSystemStrict = ownerships.mkResolveSystemStrict roster;
}
```

Import this facade from system and home modules instead of rebuilding the roster independently.

---

## NixOS without Den

Ownerships resolves plain attrsets, so a normal NixOS module can return resolved configuration directly.

### `units/system.nix`

```nix
{ pkgs }:
[
  {
    label = "shared system defaults";
    services.openssh.enable = true;
  }

  {
    label = "khion desktop";
    hosts = [ "khion" ];

    services.xserver.enable = true;
    environment.systemPackages = [ pkgs.helix ];
  }

  {
    label = "lumi power settings";
    hosts = [ "lumi" ];

    services.tlp.enable = true;
  }
]
```

### `configuration.nix`

```nix
{ lib, pkgs, ... }:
let
  ownership = import ./ownerships.nix {
    inherit lib;
  };

  units = import ./units/system.nix {
    inherit pkgs;
  };
in
ownership.resolveSystem units {
  host = {
    name = "khion";
    system = "x86_64-linux";
  };
}
```

The resolved attrset becomes the module configuration. Ownerships selects and merges units first; the NixOS module system processes the resulting options afterward.

Do not use Ownerships as a replacement for NixOS option merging. Resolve units that produce normal module configuration.

### Reuse the module for multiple hosts

```nix
{ lib, pkgs, hostName, hostSystem, ... }:
let
  ownership = import ./ownerships.nix {
    inherit lib;
  };
in
ownership.resolveSystem (import ./units/system.nix { inherit pkgs; }) {
  host = {
    name = hostName;
    system = hostSystem;
  };
}
```

A flake or `lib.nixosSystem` caller can supply `hostName` and `hostSystem` through `specialArgs`.

---

## Home Manager without Den

Home Manager uses user scope because both host and user claims can matter.

### `units/home.nix`

```nix
{ pkgs }:
[
  {
    label = "shared shell";
    programs.fish.enable = true;
  }

  {
    label = "feltfomo editor";
    users = [ "feltfomo" ];

    programs.helix.enable = true;
    home.packages = [ pkgs.ripgrep ];
  }

  {
    label = "khion graphical tools";
    hosts = [ "khion" ];

    home.packages = [ pkgs.ghostty ];
  }

  {
    label = "feltfomo on khion";
    hosts = [ "khion" ];
    users = [ "feltfomo" ];

    home.sessionVariables.EDITOR = "hx";
  }
]
```

### `home.nix`

```nix
{ lib, pkgs, ... }:
let
  ownership = import ./ownerships.nix {
    inherit lib;
  };

  units = import ./units/home.nix {
    inherit pkgs;
  };
in
ownership.resolve units {
  host = {
    name = "khion";
    system = "x86_64-linux";
  };
  user = {
    name = "feltfomo";
  };
}
```

Home Manager sees only the merged configuration for that host/user context.

---

## Claim keys

| Key | Value | Scope |
| --- | --- | --- |
| `hosts` | host aliases or canonical IDs | user and system |
| `exceptHosts` | host aliases or canonical IDs | user and system |
| `users` | user IDs or unique aliases | user only |
| `exceptUsers` | user IDs or unique aliases | user only |
| `when` | context predicate | user and system |

A unit with no claim is global.

Include and exclude are opposite polarities of one axis. Do not set `hosts` with `exceptHosts`, or `users` with `exceptUsers`, on the same unit.

```nix
[
  {
    programs.fish.enable = true;
  }
  {
    hosts = [ "khion" "lumi" ];
    home.sessionVariables.FLEET = "personal";
  }
  {
    exceptUsers = [ "guest" ];
    programs.git.enable = true;
  }
]
```

## Predicate claims

Use `when` when roster identity cannot express a condition:

```nix
{
  when = { host, ... }: host.gpu == "nvidia";
  home.packages = [ pkgs.nvtopPackages.nvidia ];
}
```

Predicates receive the concrete context and may read extra fields supplied by the caller. A false predicate is inactive, not structurally impossible. Matrix projection cannot prove arbitrary predicates always false.

Prefer named claims when names are enough; they provide stronger roster validation and matrix reasoning.

---

## Nesting with `children`

Children inherit and may narrow their parent’s effective claim:

```nix
resolve [
  {
    hosts = [ "khion" "lumi" ];

    children = [
      {
        home.sessionVariables.EXAMPLE = "1";
      }
      {
        hosts = [ "khion" ];
        home.packages = [ pkgs.example-desktop-tools ];
      }
    ];
  }
] context
```

The first child applies to both hosts. The second narrows to `khion`. A child cannot widen beyond its parent.

A parent may contain configuration and children simultaneously. Its payload becomes one leaf, and each config-bearing descendant becomes another leaf.

Disjoint parent and child claims are impossible declarations rather than inactive selections.

---

## Reserved keys and `value`

The unit grammar reserves claim keys plus:

- `children`
- `value`
- `label`
- `source`
- `mergeProfile`

Use `value` when configuration itself begins with a reserved key, especially NixOS `users.*`:

```nix
{
  hosts = [ "khion" ];

  value = {
    users.users.example = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
    };
  };
}
```

Claims, metadata, merge profile, and children remain outside `value`. Inline payload keys may not coexist with `value`; route the complete payload through it.

Content inside `value` is opaque configuration and is not scanned again for ownership-looking keys.

---

## Identity metadata

```nix
{
  label = "khion audio tools";
  source = "configuration/units/audio.nix";
  hosts = [ "khion" ];

  environment.systemPackages = [ pkgs.pavucontrol ];
}
```

`label` and `source` improve diagnostics, traces, and merge provenance. They do not enter resolved configuration and do not inherit into children.

Use them in nontrivial standalone unit collections so failures point back to authored declarations.

---

## Merge behavior

The ordinary profile:

- deep-merges attrsets;
- concatenates lists in source order;
- keeps equal scalar values;
- rejects different scalar values at one path;
- treats derivations as terminal and compares `outPath`;
- treats functions as unequal.

```nix
resolve [
  { packages = [ pkgs.git ]; }
  { packages = [ pkgs.helix ]; }
] context
```

produces one list in declaration order.

Conflicting scalars fail before the NixOS or Home Manager module system sees them:

```nix
resolve [
  { editor = "helix"; }
  { editor = "vim"; }
] context
```

Use a profiled resolver only when the standalone system intentionally defines merge-profile behavior:

```nix
profiledResolve = ownerships.mkResolveProfiled profileArgs roster;
value = profiledResolve units context;
```

Built-in profile names are `strict-ordered` and `last-wins`. Built-in list strategies are `ordered-concat`, `dedup-union`, and `take-right`. A profile is validated only when a selected contributor activates it.

---

## Resolver doors

| Function | Result |
| --- | --- |
| `mkResolve roster units ctx` | User-scope merged value |
| `mkResolveSystem roster units ctx` | System-scope merged value |
| `mkResolveStrict roster units ctx` | User resolve with strict context validation |
| `mkResolveSystemStrict roster units ctx` | System strict resolve |
| `mkResolveTrace roster units ctx` | User result, decisions, stages, and provenance |
| `mkResolveSystemTrace roster units ctx` | System trace |
| `mkResolveMatrix roster { units; ... }` | User fleet selection projection |
| `mkResolveSystemMatrix roster { units; ... }` | System fleet projection |
| `mkResolveProfiled args roster units ctx` | User resolve with merge profiles |
| `mkResolveSystemProfiled args roster units ctx` | System profiled resolve |

The roster argument is curried:

```nix
resolve = ownerships.mkResolve roster;
value = resolve units context;
```

### Trace one context

```nix
trace = ownerships.mkResolveTrace roster units {
  host = {
    name = "khion";
    system = "x86_64-linux";
  };
  user = {
    name = "feltfomo";
  };
};
```

Use trace to see why a unit survived, which stages ran, and which contributors produced merged paths.

### Project the roster

```nix
matrix = ownerships.mkResolveMatrix roster {
  inherit units;
};
```

A matrix runs structural, tree, and survivor validation and reports selection across modeled contexts. It deliberately does not merge payloads or build merge provenance.

---

## Impossible, inactive, and indeterminate

A declaration is **impossible** when its claim cannot select a valid roster context, for example:

- `hosts = [ ]`;
- a named member is unknown;
- a bare alias is ambiguous;
- parent and child includes are disjoint;
- an include is completely removed by an exclusion;
- a host/user combination has no compatible roster membership.

A valid claim is **inactive** when it does not match the current concrete context. Its payload is not selected or merged.

A predicate can be **indeterminate** in matrix projection because arbitrary code cannot be reduced to a finite name set. A structurally live unit may also be **never selected** across the projected contexts.

---

## Standalone troubleshooting

### Unknown host or user

Declare the member in the same roster passed to the resolver. Ownerships does not read NixOS users or flake configurations automatically.

### Ambiguous host alias

Use the canonical `<system>/<name>` identity or make the bare alias unique.

### Missing user context

Use `mkResolveSystem` for system-only units. A user resolver needs a user when selected claims demand that axis.

### System scope rejects `users`

Move the unit into user/Home Manager resolution or replace it with an appropriate host claim. System scope has no user entity.

### Matching values still conflict

Ownerships merges plain Nix values, not module definitions. Differing scalar writes conflict before NixOS or Home Manager option merging.

### A child never selects

Check the intersection of parent and child claims. Children narrow inherited ownership and cannot escape it.

### An odd context passes global units

Ordinary resolution validates only demanded axes to preserve laziness. Use a strict resolver when every supplied entity must be roster-valid.

### Selection is unclear

Use `mkResolveTrace` for one context or `mkResolveMatrix` for fleet-wide structural inspection.

---

## Program and Den integration

When using skadi, Program remains the preferred surface for packages, files, directories, and Noctalia templates:

```nix
den.aspects.example = program {
  hosts = [ "khion" "lumi" ];
  users = [ "feltfomo" ];

  pkg = pkgs: pkgs.example;

  directories = [
    {
      src = "${rootPath}/configs/example";
      dest = ".config/example";
    }
  ];
};
```

Program translates its claims and generated Home Manager, NixOS, and Furnish slices into Ownerships units.

For arbitrary aspect configuration, Den may inject resolvers already bound to the fleet roster:

```nix
{
  resolve,
  resolveSystem,
  ...
}:
{
  den.aspects.example.homeManager =
    {
      host ? null,
      user ? null,
      pkgs,
      ...
    }:
    (resolve [
      { programs.example.enable = true; }
      {
        hosts = [ "khion" ];
        home.packages = [ pkgs.example-helper ];
      }
    ]) { inherit host user; };

  den.aspects.example.nixos =
    {
      host ? null,
      pkgs,
      ...
    }:
    (resolveSystem [
      {
        hosts = [ "khion" ];
        environment.systemPackages = [ pkgs.example ];
      }
    ]) { inherit host; };
}
```

The semantics are the same:

- standalone callers import Ownerships and build the roster;
- Den supplies roster-bound resolver doors;
- Program supplies a higher-level facade for common program and managed-file declarations.

See [Program](../program.md), [Architecture](architecture.md), [Inspection](inspection.md), and [Reference](reference.md) for the surrounding subsystem documentation.
