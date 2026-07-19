# Run without den

Import the surface, build declarations, project a roster, and bind a door.

```nix
let
  ownerships = import ./modules/_lib/ownerships/surface.nix { inherit lib; };

  roster = ownerships.toRoster [
    (ownerships.define.host "khion" { system = "x86_64-linux"; })
    (ownerships.define.host "lumi" { system = "x86_64-linux"; })
    (ownerships.define.user "feltfomo" { hosts = [ "khion" "lumi" ]; })
  ];

  resolve = ownerships.mkResolve roster;
in
resolve [
  { shared = true; }
  { hosts = [ "khion" ]; desktopOnly = true; }
] {
  host = { name = "khion"; system = "x86_64-linux"; };
  user.name = "feltfomo";
}
```

A one-argument `define.host "khion"` remains a standalone declaration with canonical ID `standalone/khion` and bare alias `khion`.

Use `mkResolveStrict` when the supplied context itself must be validated against the roster. Default resolve validates claims, not an otherwise-unused context tuple.

Use `resolveWith { roster; ctx; merge ? ...; } claimTree` only when you need the lower-level engine-shaped input rather than self-labeling surface units.
