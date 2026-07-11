# _lib/program.nix
#
# The class-module shape every program-backed aspect builds on: pkg install,
# static file links, noctalia templates, a noctalia config blob, and -- for an
# aspect that also owns system config -- a host-only nixos slice. Ownership now
# rides the ownerships surface instead of scoped -- an aspect hands program a
# plain spec (as before), and any hosts/users/exceptHosts/exceptUsers/when on
# the spec or on an individual files/templates entry becomes a claim the bound
# `resolve` checks against the real build context. Untagged stays globally
# owned.
#
# Resolve is lazy: rather than an owning aspect threading its entity through a
# { host, user }: wrapper, each class module reads host (and, at user scope,
# user) straight from its OWN module args -- den injects the same entities into
# a class module that it used to hand the wrapper -- and resolves at
# class-module eval. So a bare `den.aspects.x = program { ... }` works with no
# wrapper: the home slices resolve at user scope, and the nixos slice resolves
# host-only through `resolveSystem` (no user in scope), each reading its own
# host. resolve reads an axis's ctx entity only when a claim narrows on it, so
# an untagged spec resolves globally with no ctx at all -- a bare caller like
# kitty narrows on nothing and its class modules' host/user args go unread.
{
  lib,
  resolve,
  resolveSystem,
}:
let
  # ownership claim keys a unit may carry; everything else on a files/templates
  # entry, or on the whole spec, is config value, never an owner tag.
  claimKeys = [
    "hosts"
    "users"
    "exceptHosts"
    "exceptUsers"
    "when"
  ];
  claimKeysAttrs = lib.genAttrs claimKeys (_: null);

  # a files/templates entry becomes its own leaf: its claim (if any) rides
  # alongside a singleton list keyed by the field name, so surviving entries
  # across leaves concatenate back into one list through the engine's own
  # list-merge -- program never re-assembles the list by hand. a bare
  # non-attrset entry (a module function) carries no claim and passes through.
  entryUnit =
    fieldName: entry:
    if builtins.isAttrs entry then
      (builtins.intersectAttrs claimKeysAttrs entry)
      // {
        ${fieldName} = [ (removeAttrs entry claimKeys) ];
      }
    else
      { ${fieldName} = [ entry ]; };

  # the whole spec is the root unit: its own claim narrows every field at once
  # (a whole-aspect owner), and each pkg/imports/noctaliaConfig/file/template
  # entry is a child leaf so a per-entry owner narrows only that entry. imports
  # has no per-entry selector (matching the pre-migration behavior) so it rides
  # as one leaf carrying the whole list.
  specUnit =
    spec:
    let
      pkg = spec.pkg or null;
      imports = spec.imports or [ ];
      noctaliaConfig = spec.noctaliaConfig or { };
    in
    (builtins.intersectAttrs claimKeysAttrs spec)
    // {
      children =
        lib.optional (pkg != null) { inherit pkg; }
        ++ lib.optional (imports != [ ]) { inherit imports; }
        ++ lib.optional (noctaliaConfig != { }) { inherit noctaliaConfig; }
        ++ map (entryUnit "files") (spec.files or [ ])
        ++ map (entryUnit "templates") (spec.templates or [ ]);
    };

  # home-manager CONFIG for a resolved spec: package install + noctalia template
  # activation scripts. an absent pkg/templates entry just contributes nothing --
  # resolve already dropped whatever didn't survive.
  hmConfig =
    # home-manager's extended lib (provides lib.hm.dag for activation scripts); a
    # superset of the file-level nixpkgs lib, so mkMerge / mkIf still resolve.
    lib: spec: pkgs:
    lib.mkMerge [
      # install the package if one survived resolve
      (
        let
          pkg = spec.pkg or null;
        in
        lib.mkIf (pkg != null) {
          home.packages = [ (pkg pkgs) ];
        }
      )

      # write each noctalia template into ~/.config/noctalia/templates/
      (lib.mkMerge (
        map (t: {
          home.activation."noctalia-template-${t.name}" = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            mkdir -p $HOME/.config/noctalia/templates/${t.subdir or ""}
            cat > $HOME/.config/noctalia/templates/${t.subdir or ""}${t.name} << 'EOF'
            ${builtins.readFile t.templateFile}
            EOF
          '';
        }) (spec.templates or [ ])
      ))
    ];

  # hjem file links for a resolved spec. an absent files/noctaliaConfig entry
  # just contributes nothing -- resolve already dropped whatever didn't survive.
  hjemFiles =
    spec: pkgs:
    let
      noctaliaConfig = spec.noctaliaConfig or { };
    in
    lib.mkMerge [
      # link static config files straight into home
      (lib.mkMerge (
        map (f: {
          ${f.dest}.source = f.src;
        }) (spec.files or [ ])
      ))

      # serialise noctaliaConfig to toml and link it so noctalia merges it
      (lib.mkIf (noctaliaConfig != { }) {
        ".config/noctalia/${noctaliaConfig._fileName}.toml".source =
          (pkgs.formats.toml { }).generate "noctalia-${noctaliaConfig._fileName}.toml"
            (removeAttrs noctaliaConfig [ "_fileName" ]);
      })
    ];
in
spec:
let
  # home ownership units: the whole spec as one root leaf (its claims + config
  # fields are read off it by specUnit). the nixos slice is separate -- specUnit
  # never looks at `spec.nixos`, so it can't leak into the home resolve.
  homeUnits = [ (specUnit spec) ];
in
{
  # home slices resolve at USER scope, reading host + user from their own module
  # args: den injects the same entities the old { host, user }: wrapper got.
  # both default to null so an untagged spec (which narrows on nothing) still
  # resolves globally -- resolve only reads an entity some claim narrows on.
  homeManager =
    {
      pkgs,
      lib,
      host ? null,
      user ? null,
      ...
    }:
    let
      resolved = (resolve homeUnits) { inherit host user; };
    in
    {
      imports = resolved.imports or [ ];
      config = hmConfig lib resolved pkgs;
    };

  hjem =
    {
      pkgs,
      host ? null,
      user ? null,
      ...
    }:
    let
      resolved = (resolve homeUnits) { inherit host user; };
    in
    {
      files = hjemFiles resolved pkgs;
    };
}
// lib.optionalAttrs (spec ? nixos) {
  # host-only system slice: resolves at HOST scope through resolveSystem,
  # reading host from its own args -- no user is in scope here, so user is never
  # requested and resolveSystem pins user = null. `spec.nixos` is a
  # { pkgs, config }: [ units ] function, so a unit's system config can read pkgs
  # and the host's resolved config (a service package, a sops secret path); each
  # unit carries its own hosts/... claim exactly as a standalone resolveSystem
  # call would. host is kept out of that args set -- it reaches the slice only
  # through the resolveSystem ... { inherit host; } wrapper below, so a unit
  # narrows through its own claim rather than reading a raw host.
  # only emitted when the aspect declares a nixos slice, so home-only callers
  # (kitty, noctalia, firefox) keep their exact { homeManager; hjem; } shape.
  nixos =
    {
      pkgs,
      config,
      host ? null,
      ...
    }:
    (resolveSystem (spec.nixos { inherit pkgs config; })) { inherit host; };
}
