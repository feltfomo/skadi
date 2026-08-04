# Program

`program` is the normal aspect-authoring surface for software that installs packages, imports Home Manager modules, places files, expands configuration directories, registers application themes, or emits a NixOS slice.

A declaration has no effect unless it contains a capability such as `pkg`, `imports`, `files`, `directories`, `theme`, or `nixos`.

## Minimal program

```nix
{ program, rootPath, ... }:
{
  den.aspects.ghostty = program {
    pkg = pkgs: pkgs.ghostty;
    directories = [
      {
        src = "${rootPath}/configs/ghostty";
        dest = ".config/ghostty";
      }
    ];
  };
}
```

## Theme registration

A theme declaration describes one application theme. Common intent is written once. `renderers` explicitly selects the engines that may render it.

```nix
theme = {
  id = "kitty";
  source = "${rootPath}/configs/kitty/themes/skadi.conf";
  output = ".config/kitty/themes/skadi.conf";
  reload = "pkill -SIGUSR1 kitty";

  renderers = {
    noctalia = { };
    dms = { };
    caelestia = {
      source = "${rootPath}/configs/kitty/themes/caelestia.conf";
      placedAs = "theme.conf";
    };
  };
};
```

This declaration registers Kitty with all three engines:

- Noctalia and DMS inherit the shared `source`, `output`, and `reload` fields.
- Caelestia overrides only the source format and template filename it needs.
- An omitted renderer is not registered.
- A renderer-specific field stays beside that renderer instead of being hidden behind a shared abstraction.

### Shared fields

The single-template form accepts:

- `id`: normalized application registration name.
- `source`: template source path.
- `output`: stable path below the user's home directory.
- `reload`: optional command run after publishing the rendered output.
- `subdir`: optional renderer template subdirectory.
- `placedAs`: optional template filename override.
- `subId`: optional suffix for the registration identity.
- `renderers`: explicit renderer adapter set.

Shared fields are defaults. A renderer adapter may override `source`, `output`, `reload`, `subdir`, `placedAs`, or `subId`.

### Renderer-specific fields

Noctalia and DMS adapters may also set `native` fields supported by their registration format.

```nix
theme = {
  id = "example";
  source = ./colors.conf;
  output = ".config/example/colors.conf";

  renderers.dms.native = {
    compare_to = "dark";
  };
};
```

Caelestia does not expose native per-template registration fields. Program rejects `renderers.caelestia.native` rather than pretending the backend supports it.

### Caelestia publication

Caelestia renders registered templates into its state directory. Program emits one executable publisher per application under `.config/caelestia/theme-hooks/`.

A publisher installs every output for that application before running any reload command. Entries are ordered by registration identity, and both the publisher and aggregate `postHook` stop on the first failure. This prevents a partial multi-output publication from being followed by a reload that observes only some new files.

## Multiple outputs

Use `templates` when one application publishes multiple files. `id` remains application-wide; each template declares its own `subId`, output, and renderer adapters.

```nix
theme = {
  id = "firefox";
  templates = [
    {
      subId = "chrome";
      source = "${rootPath}/configs/firefox/chrome/userChrome.css";
      output = ".config/mozilla/firefox/feltfomo/chrome/userChrome.css";
      renderers = {
        noctalia = { };
        dms = { };
        caelestia = {
          source = "${rootPath}/configs/firefox/chrome/caelestia-userChrome.css";
          placedAs = "userChrome.css";
        };
      };
    }
    {
      subId = "content";
      source = "${rootPath}/configs/firefox/chrome/userContent.css";
      output = ".config/mozilla/firefox/feltfomo/chrome/userContent.css";
      renderers = {
        noctalia = { };
        dms = { };
        caelestia = {
          source = "${rootPath}/configs/firefox/chrome/caelestia-userContent.css";
          placedAs = "userContent.css";
        };
      };
    }
  ];
};
```

The multi-template form does not mix shared single-template fields beside `templates`. Put template fields inside each list entry.

## Compositor themes

Compositors register only with the shell engine used in that session.

```nix
theme = {
  id = "hyprland";
  source = "${rootPath}/configs/hypr/caelestia-colors.lua";
  output = ".config/hypr/colors.lua";
  reload = "hyprctl reload";
  renderers.caelestia.placedAs = "colors.lua";
};
```

Niri uses `renderers.dms`; Mango uses `renderers.noctalia`.

## Files

```nix
files = [
  {
    src = "${rootPath}/configs/example/config.toml";
    dest = ".config/example/config.toml";
  }
];
```

Optional file lifecycle fields are `representation`, `onConflict`, and `provenance`.

## Directories

```nix
directories = [
  {
    src = "${rootPath}/configs/example";
    dest = ".config/example";
    exclude = [ "generated.conf" ];
    files = [
      {
        names = [ "state.json" ];
        representation = "writable";
        onConflict = "source-wins";
      }
    ];
  }
];
```

Directory expansion manages regular files recursively. Theme sources under that directory are reserved automatically and are not also emitted as ordinary files.

## Ownership

Program declarations and nested file, directory, or theme entries accept Ownerships claims such as `hosts`, `users`, `exceptHosts`, `exceptUsers`, and `when`.

Prefer the highest declaration level that accurately expresses ownership. Use nested claims only when one capability has narrower ownership than the rest of the program.

## Validation

Program uses a closed declaration schema. It rejects unknown fields, malformed destinations, unsupported renderer fields, duplicate registration identities, invalid conflict policies, and theme sources hidden under excluded directory subtrees.

Payloads selected by Ownerships are validated before Program emits Furnish declarations.
