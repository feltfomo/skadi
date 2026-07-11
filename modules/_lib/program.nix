# _lib/program.nix
#
# The class-module shape every program-backed aspect builds on: pkg install,
# static file links, noctalia templates, and a noctalia config blob. Ownership
# now rides the ownerships surface instead of scoped -- an aspect hands program
# a plain spec (as before), and any hosts/users/exceptHosts/exceptUsers/when on
# the spec or on an individual files/templates entry becomes a claim the bound
# `resolve` checks against the real build context. Untagged stays globally
# owned. host/user arrive as plain args from an owning aspect's own { host,
# user }: wrapper (den fans an aspect out that way, not through a class
# module's own arg set) and default to null. resolve reads an axis's ctx entity
# only when a claim narrows on it, so an untagged spec resolves globally with no
# ctx at all -- a bare caller like kitty passes neither host nor user, and an
# aspect that does narrow on a host is the one that threads its entity through
# the wrapper.
{ lib, resolve }:
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
{
  # the build ctx resolve checks a narrowing claim against: real entities an
  # owning aspect threads in from its own { host, user }: wrapper. they default
  # to null because an untagged spec never narrows, so resolve reads no entity
  # and a bare caller (kitty, noctalia, firefox) supplies neither.
  host ? null,
  user ? null,
  # ownership claims (hosts/users/exceptHosts/exceptUsers/when) and config
  # fields (pkg/files/templates/imports/noctaliaConfig) arrive inside `spec`
  # through the `...` below and are read off it by specUnit -- they are NOT
  # named formals. untagged on all of these means globally owned. keeping `...`
  # also means a caller like hyprland.nix that passes host/user/files keeps
  # working unchanged.
  ...
}@spec:
let
  resolved = (resolve [ (specUnit spec) ]) { inherit host user; };
in
{
  homeManager =
    { pkgs, lib, ... }:
    {
      imports = resolved.imports or [ ];
      config = hmConfig lib resolved pkgs;
    };

  hjem =
    { pkgs, ... }:
    {
      files = hjemFiles resolved pkgs;
    };
}
