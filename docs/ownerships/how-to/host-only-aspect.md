# Write host-only config

Use the system door for config that binds a host but no user. In skadi this normally means returning units from `program`'s `nixos` field.

```nix
den.aspects.audio = program {
  nixos = { pkgs, ... }: [
    {
      hosts = [ "khion" "lumi" ];
      environment.systemPackages = [ pkgs.pavucontrol ];
      services.pipewire.enable = true;
    }
  ];
};
```

A spec-level host claim narrows home slices. It does not flow into `nixos`, because home and system content resolve through different scopes. Put the host claim on the returned system unit.

System scope rejects `users` and `exceptUsers` anywhere in the tree. There is no user entity to select.

When only one field is host-specific, keep the common content global and narrow the small slice:

```nix
nixos = { ... }: [
  { services.example.enable = true; }
  {
    hosts = [ "khion" ];
    services.example.keepWarm = true;
  }
];
```

Don't wrap the whole block in a host claim unless every field is genuinely host-specific.
