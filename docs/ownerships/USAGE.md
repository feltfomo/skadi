# Using ownerships

Ownerships lets config say who it belongs to without wrapping an aspect in host/user conditionals. Put a claim on the config unit. Leave claims off when the config belongs everywhere.

In skadi, start with `program`. Use the bound `resolve` or `resolveSystem` module args when the `program` shape doesn't fit.

## The claim keys

| Key | Meaning | Available in |
| --- | --- | --- |
| `hosts = [ ... ]` | only these hosts | user and system scope |
| `exceptHosts = [ ... ]` | every host except these | user and system scope |
| `users = [ ... ]` | only these users | user scope |
| `exceptUsers = [ ... ]` | every user except these | user scope |
| `when = ctx: ...` | where the predicate returns true | user and system scope |

Host names may be unique bare aliases such as `"workstation"` or canonical IDs such as `"x86_64-linux/workstation"`. Use the canonical form when one bare name exists on more than one system.

A unit with no claim is global.

## Most aspects: use `program`

`program` is a module argument already bound to the fleet. It can install one package, add Home Manager imports, link files with hjem, write Noctalia templates/config, and emit an optional NixOS slice.

### Global package and file

```nix
{
  program,
  rootPath,
  ...
}:
{
  den.aspects.example = program {
    pkg = pkgs: pkgs.example;
    files = [
      {
        dest = ".config/example/config.toml";
        src = "${rootPath}/configs/example/config.toml";
      }
    ];
  };
}
```

There is no ownership key, so the home content is global.

### Limit all home content to some hosts

```nix
den.aspects.example = program {
  hosts = [ "workstation" "laptop" ];

  pkg = pkgs: pkgs.example;
  files = [
    {
      dest = ".config/example/config.toml";
      src = "${rootPath}/configs/example/config.toml";
    }
  ];
};
```

The spec-level claim narrows `pkg`, `imports`, `files`, `templates`, and `noctaliaConfig` together.

### Limit one file

`files` and `templates` entries can carry their own claims:

```nix
den.aspects.example = program {
  pkg = pkgs: pkgs.example;

  files = [
    {
      dest = ".config/example/config.toml";
      src = "${rootPath}/configs/example/config.toml";
    }
    {
      hosts = [ "workstation" ];
      dest = ".config/example/hardware.toml";
      src = "${rootPath}/configs/example/hardware-workstation.toml";
    }
  ];
};
```

The first file and package are global. Only `hardware.toml` is host-specific.

### Add system config

`nixos` returns system-scope units. Its units own themselves; a claim on the outer `program` spec does not flow into them.

```nix
{
  program,
  rootPath,
  ...
}:
{
  den.aspects.example = program {
    hosts = [ "workstation" "laptop" ]; # home content

    pkg = pkgs: pkgs.example;
    files = [
      {
        dest = ".config/example/config.toml";
        src = "${rootPath}/configs/example/config.toml";
      }
    ];

    nixos = { pkgs, config, ... }: [
      {
        hosts = [ "workstation" "laptop" ]; # system content
        programs.example.enable = true;
        environment.systemPackages = [ pkgs.example-helper ];
      }
    ];
  };
}
```

System scope has a host but no user. `users` and `exceptUsers` are rejected there.

When most system config is global and one field is host-specific, split it into separate units:

```nix
nixos = { ... }: [
  {
    services.example.enable = true;
  }
  {
    hosts = [ "workstation" ];
    services.example.keepWarm = true;
  }
];
```

## User claims

User claims belong to home/user scope:

```nix
den.aspects.example = program {
  users = [ "primary" ];
  pkg = pkgs: pkgs.example;
};
```

Negative claims stay open to future roster members:

```nix
den.aspects.example = program {
  exceptUsers = [ "guest" ];
  pkg = pkgs: pkgs.example;
};
```

Do not set both `users` and `exceptUsers` on one unit. The same rule applies to `hosts` and `exceptHosts`.

## Predicate claims

Use `when` when a name list cannot express the condition:

```nix
den.aspects.example = program {
  when = { host, ... }: host.gpu == "vendor-a";
  pkg = pkgs: pkgs.example-gpu-tools;
};
```

Predicates are checked only against the current context. A predicate that returns false is inactive, not impossible. Reading a missing context field throws normally, so prefer name claims when names are enough.

## Direct user-scope config with `resolve`

Use the bound `resolve` module arg when you need arbitrary Home Manager config instead of the `program` fields.

```nix
{
  resolve,
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
      {
        programs.example.enable = true;
      }
      {
        hosts = [ "workstation" ];
        home.packages = [ pkgs.example-helper ];
      }
    ]) { inherit host user; };
}
```

`resolve` is already bound to the fleet roster. Give it a list of units, then the `{ host; user; }` context supplied to the class module.

## Direct system config with `resolveSystem`

```nix
{
  resolveSystem,
  ...
}:
{
  den.aspects.example.nixos =
    {
      host ? null,
      pkgs,
      ...
    }:
    (resolveSystem [
      {
        hosts = [ "workstation" ];
        environment.systemPackages = [ pkgs.example ];
      }
    ]) { inherit host; };
}
```

Do not pass a user or use user claims through `resolveSystem`.

## Nest related units with `children`

A child inherits and may narrow its parent's claim:

```nix
(resolve [
  {
    hosts = [ "workstation" "laptop" ];
    children = [
      {
        home.sessionVariables.EXAMPLE = "1";
      }
      {
        hosts = [ "workstation" ];
        home.packages = [ pkgs.example-desktop-tools ];
      }
    ];
  }
]) { inherit host user; }
```

The first child applies to both hosts. The second narrows the parent to `workstation`. A child cannot widen beyond the parent.

## Config paths that collide with ownership keys

Use `value` when real config starts with a reserved key, especially NixOS `users.*`:

```nix
{
  hosts = [ "workstation" ];
  value = {
    users.users.example.isNormalUser = true;
  };
}
```

Put the entire payload inside `value`. Mixing `value` with inline config on the same unit is rejected. Claims, `children`, `label`, `source`, and `mergeProfile` may remain outside it.

This escape hatch is available on raw units passed to `resolve`/`resolveSystem`, including units returned by `program.nixos`. It is not a `program` home-spec field.

## Labels make errors useful

```nix
{
  label = "workstation service";
  hosts = [ "workstation" ];
  services.example.enable = true;
}
```

`label` and `source` identify a unit in diagnostics and traces. They never enter merged config and do not inherit into children.

## What merging does

After selection:

- attrsets merge recursively;
- lists append in source order by default;
- equal scalar values survive;
- different scalar values at the same path fail as a conflict.

Ownerships runs before the NixOS/Home Manager module systems. It does not understand option types, priorities, `mkDefault`, or `mkForce`. Resolve units into module config; do not treat ownerships as a replacement for typed module merging.

## What failures mean

- **Inactive:** the claim is valid but does not match this build. The unit disappears silently.
- **Impossible:** a name is unknown, nesting produces an empty set, or two claimed axes have no compatible roster pair. Resolution fails before selection.
- **Conflict:** selected co-owners set incompatible scalar values.

Bare host aliases that resolve to several canonical hosts are rejected. Qualify them as `system/name`.

## Which API is public to an aspect author

The skadi flake injects these module args:

- `program`: normal package/file/template/NixOS aspect authoring;
- `resolve`: arbitrary user-scope units, already roster-bound;
- `resolveSystem`: arbitrary system-scope units, already roster-bound.

Constructors such as `mkResolve`, strict variants, traces, matrices, descriptors, and profiled resolvers are library and audit surfaces. Normal aspects should not rebuild or rebind the roster.

## Gate a change

```bash
nix fmt
nix flake check
```

Run those from the repository root after changing an ownership claim or consumer.

For exact signatures and advanced inspection functions, see [Surface API](reference/surface-api.md). For the unit grammar, see [Claim and unit keys](reference/claim-and-unit-keys.md).
