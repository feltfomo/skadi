# Route reserved config through `value`

Use `value` when a real config path begins with a reserved unit key. NixOS `users.*` is the common case.

```nix
{
  label = "local account";
  hosts = [ "khion" ];
  value = {
    users.users.alice.isNormalUser = true;
  };
}
```

The surface reads claims and metadata from the outer unit, then passes the `value` attrset verbatim as the payload. It does not scan inside `value` for claim-looking names.

`value` may sit beside claims, `children`, `label`, `source`, and `mergeProfile`. It may not sit beside inline config:

```nix
# rejected
{
  value.users.users.alice.isNormalUser = true;
  environment.systemPackages = [ pkgs.git ];
}
```

Put all payload keys inside `value` instead. Inline form stays preferable when there is no collision.
