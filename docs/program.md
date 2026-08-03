# Program

`program` is the normal aspect-authoring facade for software that may install a package, import Home Manager modules, place managed files, expand a configuration directory, register Noctalia or DMS application templates, or emit NixOS configuration.

It combines three internal systems:

- **Ownerships** decides which declarations apply to the current host and user.
- **Program** validates and expands the selected declaration.
- **Furnish** turns selected files into managed filesystem state.

Most aspect authors should use `program` instead of importing those systems directly.

## Minimal example

```nix
{
  program,
  rootPath,
  ...
}:
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

This installs Ghostty for every selected Home Manager user and manages every regular file beneath `configs/ghostty` under `~/.config/ghostty`.

## Declaration reference

A Program declaration accepts these top-level fields:

| Field | Type | Purpose |
| --- | --- | --- |
| `pkg` | `pkgs: package` | Add one package to `home.packages`. |
| `imports` | list | Add Home Manager imports. |
| `nixos` | `{ pkgs, config, ... }: units` | Produce system-scope Ownerships units. |
| `files` | list | Declare individual managed files. |
| `directories` | list | Expand a source directory into managed files. |
| `theme.noctalia` | attrset | Seed and register Noctalia templates. |
| `theme.dms` | attrset | Seed and register DMS/Matugen templates. |
| Ownership claim keys | varies | Narrow the Home Manager and file-producing portion. |

Unknown top-level fields are errors. Program is intentionally a bounded facade, not an open-ended attrset that forwards arbitrary Home Manager options.

## Ownership claims

The following keys can appear on the Program declaration and on supported nested entries:

| Key | Meaning |
| --- | --- |
| `hosts = [ ... ]` | Include only these hosts. |
| `exceptHosts = [ ... ]` | Include every host except these hosts. |
| `users = [ ... ]` | Include only these users. |
| `exceptUsers = [ ... ]` | Include every user except these users. |
| `when = ctx: ...` | Include the declaration when the predicate returns true. |

No claim means global ownership.

Top-level claims narrow `pkg`, `imports`, `files`, `directories`, `theme.noctalia`, and `theme.dms`. Nested file, directory, directory-rule, and theme entries may narrow that ownership further. A child cannot widen the ownership inherited from its parent.

```nix
den.aspects.example = program {
  hosts = [ "khion" "lumi" ];
  pkg = pkgs: pkgs.example;

  files = [
    {
      dest = ".config/example/config.toml";
      src = "${rootPath}/configs/example/config.toml";
    }
    {
      hosts = [ "khion" ];
      dest = ".config/example/gpu.toml";
      src = "${rootPath}/configs/example/gpu.toml";
    }
  ];
};
```

The package and first file apply to both hosts. The second file applies only to `khion`.

Do not put both polarities of one axis on the same entry. For example, `hosts` and `exceptHosts` cannot coexist.

## Packages and Home Manager imports

`pkg` receives the Home Manager package set:

```nix
program {
  pkg = pkgs: pkgs.helix;
}
```

Use `imports` when the program needs a Home Manager module rather than only a package:

```nix
program {
  imports = [ ./home-module.nix ];
}
```

If neither `pkg` nor `imports` is present, Program does not emit a Home Manager slice merely because files are declared. Files are handled through the NixOS/Furnish path.

## Individual files

Each `files` entry accepts:

| Field | Required | Meaning |
| --- | --- | --- |
| `src` | yes | Source path or path-like value. |
| `dest` | yes | Destination relative to the selected user's home. |
| `label` | no | Human-readable declaration identity. |
| `representation` | no | `symlink` by default, or `writable`. |
| `onConflict` | no | `error`, `source-wins`, or `runtime-wins`. |
| `provenance` | no | Source string recorded in the Furnish manifest. |
| Ownership claims | no | Further narrow this entry. |

```nix
files = [
  {
    src = "${rootPath}/configs/helix/config.toml";
    dest = ".config/helix/config.toml";
  }
  {
    src = "${rootPath}/configs/app/state.json";
    dest = ".config/app/state.json";
    representation = "writable";
    onConflict = "runtime-wins";
    provenance = "modules/aspects/app.nix";
  }
];
```

A symlink destination is reconciled to the retained source artifact. A writable destination is materialized as ordinary content and then governed by its conflict policy.

## Directories

A directory entry recursively discovers regular files beneath `src` and maps them beneath `dest`.

```nix
directories = [
  {
    src = "${rootPath}/configs/ghostty";
    dest = ".config/ghostty";
  }
];
```

Directory fields are:

| Field | Required | Meaning |
| --- | --- | --- |
| `src` | yes | Existing source directory in the evaluated flake. |
| `dest` | yes | Home-relative destination directory. |
| `exclude` | no | Relative files or subtrees to omit. |
| `files` | no | Per-file override rules. |
| `representation` | no | Default representation for discovered files. |
| `onConflict` | no | Default conflict policy. |
| `provenance` | no | Default provenance string. |
| Ownership claims | no | Further narrow the directory. |

Paths in `exclude` and override `names` must be normalized relative paths. Empty components, `.`, `..`, and absolute paths are rejected.

### Excluding files and subtrees

```nix
directories = [
  {
    src = "${rootPath}/configs/example";
    dest = ".config/example";
    exclude = [
      "generated.json"
      "cache"
    ];
  }
];
```

Excluding a directory prunes its entire subtree.

### Overriding selected files

Use `files` rules inside a directory to change lifecycle behavior for named members:

```nix
directories = [
  {
    src = "${rootPath}/configs/example";
    dest = ".config/example";
    files = [
      {
        names = [ "state.json" ];
        representation = "writable";
        onConflict = "runtime-wins";
      }
      {
        names = [ "machine.toml" ];
        hosts = [ "khion" ];
      }
    ];
  }
];
```

A file named by an override is removed from the inherited/default set and emitted only through that rule. Duplicate overrides, unknown names, overrides beneath excluded paths, and overrides of renderer-reserved theme sources are errors.

### Empty and untracked directories

Git does not record empty directories. Git-backed flakes also omit untracked files. A locally visible but empty or untracked directory therefore does not exist in the store-backed source used during evaluation.

Program reports this as `program/directory-source-missing` and includes the evaluated source path. Add a tracked file beneath the directory or remove the declaration.

A source that exists but is a regular file produces the separate `program/directory-source-kind` diagnostic.

## Noctalia templates

Program supports one Noctalia block:

```nix
theme.noctalia = {
  id = "example";
  source = "${rootPath}/themes/example.mustache";
  output = ".config/example/theme.toml";
};
```

For multiple registrations, use `templates`:

```nix
theme.noctalia = {
  id = "example";
  templates = [
    {
      source = "${rootPath}/themes/colors.mustache";
      output = ".config/example/colors.toml";
    }
    {
      source = "${rootPath}/themes/layout.mustache";
      output = ".config/example/layout.toml";
      subdir = "example/layouts";
      placedAs = "default.mustache";
      subId = "layout";
      reload = "systemctl --user restart example.service";
    }
  ];
};
```

Each template accepts:

- `source`, the seed template;
- `output`, the rendered path relative to the home;
- `subdir`, the directory beneath `.config/noctalia/templates`;
- `placedAs`, the seed filename;
- `subId`, a registration suffix;
- `reload`, an optional post-render hook;
- Ownership claims.

If `subdir` is omitted, the block `id` is used. If it is `null` or empty, the seed is placed directly under the templates root. Registration IDs must be unique.

When a template source lives inside a declared directory, Program reserves it so the ordinary directory expansion does not also furnish it to the directory destination.

## DMS templates

DMS uses the same declaration shape under an independent backend:

```nix
theme.dms = {
  id = "example";
  source = "${rootPath}/themes/example.mustache";
  output = ".config/example/theme.toml";
};
```

Program places DMS seed templates under `.config/matugen/dms/templates` and emits one composable Matugen fragment per block under `.config/matugen/dms/configs`. DMS merges those fragments when it renders a theme, so separate aspects do not compete for a single user-owned `config.toml`.

The template source is passed through unchanged. DMS-only expressions such as `dank16` therefore remain available without requiring a Noctalia declaration. Conversely, a Noctalia-only template can use its full template language without a DMS declaration.

Use `native` for renderer registration fields that Program does not model directly:

```nix
theme.dms = {
  id = "example";
  source = "${rootPath}/themes/example.mustache";
  output = ".config/example/theme.toml";
  native = {
    compare_to = "dark";
  };
};
```

Program retains ownership of `input_path`, `output_path`, and the optional `post_hook` produced from `reload`; other native fields pass through to the selected renderer.

### Sharing and divergence

Sharing is explicit ordinary Nix reuse:

```nix
let
  shared = {
    source = "${rootPath}/themes/portable.mustache";
    output = ".config/example/theme.toml";
  };
in
{
  theme = {
    noctalia = { id = "example"; } // shared;
    dms = { id = "example"; } // shared;
  };
}
```

Declare only one backend for an engine-specific template. Use separate `source` values when both backends target the same output but need different syntax. Cross-backend output reuse is intentional: only the renderer selected by the active compositor session should run.

Shell palettes are not translated by Program. Noctalia retains its native palette schema, while DMS retains its custom themes, Matugen scheme controls, and `dank16` palette.

## NixOS configuration

`nixos` returns a list of system-scope Ownerships units:

```nix
program {
  pkg = pkgs: pkgs.example;

  nixos = { pkgs, config, ... }: [
    {
      services.example.enable = true;
    }
    {
      hosts = [ "khion" ];
      environment.systemPackages = [ pkgs.example-helper ];
    }
  ];
};
```

Top-level Program claims do **not** flow into `nixos`. The Home Manager/file side and system side resolve in different scopes. Repeat any host claim needed by a returned NixOS unit.

System scope binds a host but no user. `users` and `exceptUsers` are rejected in these units.

Returned units use the complete Ownerships unit grammar, including `children`, `label`, `source`, and the `value` escape hatch. Use `value` when real NixOS configuration begins with a reserved ownership key:

```nix
nixos = { ... }: [
  {
    hosts = [ "khion" ];
    value.users.users.example.isNormalUser = true;
  }
];
```

## Validation and laziness

Program validates the outer declaration shape immediately. File, directory, override, and theme payload validation happens after Ownerships selection.

This ordering is deliberate:

- malformed selected payloads fail;
- malformed inactive payloads remain lazy;
- an inactive directory source is not traversed;
- selected directory inventories and semantic conflicts are fully checked before Furnish declarations are emitted.

Program aggregates declaration diagnostics where possible and renders them through Krisis.

## What Program emits

Depending on the declaration, Program returns one or both of:

- `homeManager`: imports plus the optional package;
- `nixos`: the raw system slice and/or Furnish runtime declarations.

Program adds `modules/_lib/furnish/runtime.nix` when it owns files. Selected file entries are converted to one Furnish declaration per selected user principal. If file content reaches a host with no user principal, the generated module assertion fails rather than silently dropping the files.

## Common failures

### Unknown field

Program has a closed schema. A misspelled field fails with a `program/*-fields` diagnostic instead of being ignored.

### Missing directory source

The directory is absent from the evaluated flake. This commonly means it is empty or contains only untracked files.

### Unknown directory override

An override names a file that was not found in the source inventory, or that was excluded.

### Duplicate theme registration

Two templates in one renderer block produced the same registration ID. Set distinct `subId` values.

### Ownership contradiction

A selected declaration contains an unknown owner, a disjoint parent/child claim, or an impossible host/user pair. Ownerships rejects it before Program expands the payload.

### Furnish collision

Two selected declarations target the same canonical filesystem identity. Furnish reports every claimant rather than choosing one.

## Maintainer model

Program is an adapter, not a general merge engine.

1. `validateSpec` checks the bounded outer vocabulary.
1. `furnishUnit` and `specUnit` translate Program fields into Ownerships trees.
1. Ownerships selects home/file content for `{ host; user; }` and system units for `{ host; }`.
1. `validateSelected` validates selected files, expands directories, and normalizes renderer-tagged themes.
1. `furnish.files.mkDeclarations` lowers home-relative files to principal-aware declarations.
1. Furnish compiles those declarations into the host manifest.

Keep these boundaries intact when extending Program:

- new user-facing fields must be added to the closed schema and validation;
- payload validation must remain after ownership selection when inactive values must stay lazy;
- `nixos` must remain a separate system-scope unit list;
- Program should not duplicate Ownerships selection or Furnish lifecycle logic;
- diagnostics must identify the author path and distinguish shape, missing-source, inventory, and semantic failures.

## Verification

From the repository root:

```fish
nix fmt
nix flake check -L
```
