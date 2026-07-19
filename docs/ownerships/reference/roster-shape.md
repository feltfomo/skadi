# Roster shape

The default projected roster contains:

```nix
{
  hosts = [ "x86_64-linux/khion" ... ];
  users = [ "feltfomo" ... ];
  membership = { "x86_64-linux/khion" = [ "feltfomo" ]; };
  usersWithUnknownMembership = [ ];
  aliases = {
    host.khion = [ "x86_64-linux/khion" ];
  };
  display = {
    host."x86_64-linux/khion" = "khion";
    user.feltfomo = "feltfomo";
  };
  dimensions = {
    <name> = {
      members = [ ... ];
      byHost."x86_64-linux/khion" = <value>;
    };
  };
}
```

Custom descriptors may add fields such as `roles` through their roster projector.

Canonical host IDs are stable keys throughout selection, matrix rows, diffs, membership, and diagnostics. `display` is presentation only. Bare aliases are accepted when they resolve uniquely.

Standalone `define.host name` accepts `system`, `dimensions`, and `aliases`. `define.user name` accepts `hosts ? null` and `id ? name`.
