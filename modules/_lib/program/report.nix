# one diagnostics policy for the whole program subsystem. program.nix builds
# declarations, the theme compiler elaborates them, and the matugen runtime
# module aggregates cross-aspect entries, and an author gets the same error
# shape from all three.
{ lib }:
let
  krisis = import ../krisis { inherit lib; };
in
{
  problem = krisis.mkDiagnosticFactory {
    severity = "error";
    codePrefix = "program";
  };

  reporter = krisis.mkReporter {
    formatHeader = count: "program: ${toString count} declaration error(s)";
    formatDiagnostic = diagnostic: "  - " + krisis.renderPlain diagnostic;
  };

  # every duplicate-registration check groups by id and names the repeats.
  duplicateValues =
    values:
    builtins.attrNames (
      lib.filterAttrs (_: group: builtins.length group > 1) (builtins.groupBy (value: value) values)
    );
}
