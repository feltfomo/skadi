# Using Ownerships

Ownerships lets configuration state who it belongs to without wrapping an entire aspect in host and user conditionals.

In skadi, prefer `program`. Use injected `resolve` and `resolveSystem` for arbitrary configuration units.

## Claim keys

| Key | Value | Scope |
| --- | --- | --- |
| `hosts` | list of host aliases or canonical IDs | user and system |
| `exceptHosts` | list of host aliases or canonical IDs | user and system |
| `users` | list of user IDs or unique aliases | user only |
| `exceptUsers` | list of user IDs or unique aliases | user only |
| `when` | context predicate | user and system |

A unit with no claim is global.

Canonical host identity is `<system>/<name>`, such as `x86_64-linux/khion`. A unique bare alias such as `khion` is accepted. An alias that resolves to multiple canonical members is rejected.

Include and exclude are opposite polarities of one axis. Do not set both on the same unit.

## Program usage

Program claims narrow its Home Manager and managed-file content:

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

File, directory, directory-override, and Noctalia template entries may carry narrower claims. See `docs/program.md` for the complete facade.

## Direct user-scope resolution

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
      { programs.example.enable = true; }
      {
        hosts = [ "khion" ];
        home.packages = [ pkgs.example-helper ];
      }
      {
        exceptUsers = [ "guest" ];
        home.sessionVariables.EXAMPLE = "1";
      }
    ]) { inherit host user; };
}
```

`resolve` is already bound to the fleet roster. It receives a unit list and then the concrete user-scope context.

## Direct system-scope resolution

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
      { services.example.enable = true; }
      {
        hosts = [ "khion" ];
        environment.systemPackages = [ pkgs.example ];
      }
    ]) { inherit host; };
}
```

System scope has no user entity. Any nested `users` or `exceptUsers` claim is rejected before resolution.

## Nesting with `children`

Children inherit and may narrow their parent's effective claim:

```nix
(resolve [
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
]) { inherit host user; }
```

The first child applies to both hosts. The second narrows to `khion`. A child cannot widen beyond its parent.

A parent may contain configuration and children simultaneously. Its own payload becomes one leaf; each config-bearing descendant becomes another leaf.

## Predicate claims

Use `when` when roster names cannot express the condition:

```nix
{
  when = { host, ... }: host.gpu == "nvidia";
  home.packages = [ pkgs.nvtopPackages.nvidia ];
}
```

A predicate returning false is inactive, not impossible. Matrix projection cannot prove an always-false predicate dead because predicates do not have a finite declared domain.

Predicates receive the concrete context. Reading a missing field throws normally, so use name claims when names are sufficient.

## Reserved config keys and `value`

The unit grammar reserves claim keys plus:

- `children`
- `value`
- `label`
- `source`
- `mergeProfile`

Use `value` when actual configuration begins with a reserved key, especially NixOS `users.*`:

```nix
{
  hosts = [ "khion" ];
  value = {
    users.users.example.isNormalUser = true;
  };
}
```

Claims, identity metadata, merge profile, and children remain outside `value`. Inline payload keys may not coexist with `value`; route the whole payload through it.

Content inside `value` is never scanned again for ownership-looking names.

## Identity metadata

```nix
{
  label = "khion audio tools";
  source = "modules/aspects/audio.nix";
  hosts = [ "khion" ];
  environment.systemPackages = [ pkgs.pavucontrol ];
}
```

`label` and `source` improve diagnostics, traces, and provenance. They do not enter merged output and do not inherit into children.

When neither exists, Ownerships identifies an unlabeled unit by shallow payload shape without forcing values.

## Merge behavior

The ordinary profile:

- deep-merges attrsets;
- concatenates lists in source order;
- keeps equal scalars;
- rejects different scalar values at one path;
- treats derivations as terminal and compares their `outPath`;
- treats functions as unequal.

Ownerships merges plain values before the NixOS/Home Manager module systems see them. Resolve to module configuration; do not use Ownerships as a replacement for module option merging.

## Impossible versus inactive

A declaration is impossible when, for example:

- `hosts = [ ]`;
- a named member is unknown;
- parent and child includes are disjoint;
- an include is completely removed by an exclusion;
- a claimed host/user pair has no compatible roster membership;
- a bare alias is ambiguous.

A valid claim is inactive when it simply does not match the current context. Its payload is neither selected nor merged.

## Standalone use

```nix
let
  ownerships = import ./modules/_lib/ownerships { inherit lib; };

  roster = ownerships.toRoster [
    (ownerships.define.host "khion" { system = "x86_64-linux"; })
    (ownerships.define.user "feltfomo" { hosts = [ "khion" ]; })
  ];

  resolve = ownerships.mkResolve roster;
in
resolve [
  { shared = true; }
  { hosts = [ "khion" ]; desktop = true; }
] {
  host = {
    name = "khion";
    system = "x86_64-linux";
  };
  user.name = "feltfomo";
}
```

One-argument `define.host "khion"` creates canonical ID `standalone/khion` and alias `khion`.

Use strict resolvers when the supplied context itself must be roster-valid. Ordinary resolvers validate authored claims and read only context entities demanded by narrowed axes.
