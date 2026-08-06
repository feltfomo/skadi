{ lib }:
{
  acceptsNative = true;
  templateRoot = ".config/matugen/dms/templates";
  templateNameOf = entry: "${entry.subdir}${entry.placedAs}";
  # matugen only ever reads templates registered in the single
  # $HOME/.config/matugen/config.toml (there is no include/merge mechanism in
  # matugen itself). A per-block file here would just be dead weight matugen
  # never looks at, and worse, if it wrote directly to config.toml, every
  # aspect declaring a dms block would collide trying to own that path (each
  # program.nix invocation only sees its own spec). Registration instead
  # happens once, globally, in program/theme/dms-runtime.nix, which is wired
  # up the same way furnish/runtime.nix is: imported from every aspect, but
  # evaluated once by the module system, after every aspect's entries have
  # merged.
  filesFor = _: [ ];
  # pure per-entry -> matugen registration mapping, reused by dms-runtime.nix
  # once it has every aspect's entries in hand.
  registrationOf =
    entry:
    let
      # matugen does NOT expand `~` -- it treats it as a literal path
      # component and silently fails to read/write the template. The
      # DankLinux docs require absolute paths. Each entry already carries
      # its principal, whose managedRoot resolves to the user's home.
      home = lib.removeSuffix "/" (entry.principal.managedRoot or "/home/${entry.principal.authority.identity}");
    in
    entry.native
    // {
      input_path = "${home}/.config/matugen/dms/templates/${entry.subdir}${entry.placedAs}";
      output_path = "${home}/${entry.output}";
    }
    // lib.optionalAttrs (entry.reload != null) { post_hook = entry.reload; };
}
