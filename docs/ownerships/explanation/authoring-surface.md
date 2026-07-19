# Authoring surface

A unit is a plain attrset with config, optional claims, and optional metadata.

```nix
{
  label = "khion audio tools";
  hosts = [ "khion" ];
  environment.systemPackages = [ pkgs.pavucontrol ];
}
```

`label` identifies the unit in diagnostics and traces. It never reaches merged config.

## Claims

- `hosts` and `users` include named members.
- `exceptHosts` and `exceptUsers` include everyone except named members.
- `when` is a predicate of the build context.
- An omitted axis is global.

A unit can't set both polarities of one axis. Use nesting when you need “A except B”:

```nix
{
  hosts = [ "khion" "lumi" ];
  children = [
    {
      exceptHosts = [ "lumi" ];
      services.example.enable = true;
    }
  ];
}
```

The child owns khion. If the child removed both hosts, its effective claim would be impossible rather than a silent no-op.

## Narrow-only nesting

Composition meets the parent's effective claim with the child's own claim on every registered axis. Missing keys use that axis's `top`, so a child can't widen its parent.

A node without config can exist only to scope its children:

```nix
{
  hosts = [ "khion" ];
  children = [
    { services.a.enable = true; }
    { services.b.enable = true; }
  ];
}
```

## Unit identity

`label` and `source` are optional strings. They don't inherit into children. When neither exists, diagnostics use a shallow payload shape such as `{ packages, services }`. The renderer never serializes the real payload just to name a unit.

## Reserved keys and `value`

The surface reserves claim keys plus `children`, `value`, `label`, `source`, and `mergeProfile`. Use `value` when real config begins with one of those names:

```nix
{
  hosts = [ "khion" ];
  value.users.users.alice.isNormalUser = true;
}
```

Claims and children may sit beside `value`. Inline config may not. Mixing the two payload forms is rejected because there is no useful reason to make routing shape-dependent.

## `program`

Most skadi aspects author through `program`, not the raw surface. Spec-level claims narrow home slices. A `nixos` function returns its own system-scope unit list, so those units repeat any host claim they need. See [surface API](../reference/surface-api.md).
