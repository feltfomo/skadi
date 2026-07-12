# _lib/ownerships/safe-render.nix
#
# One rule, shared by every error path that might touch a co-owned or claimed
# value: never force a derivation, never toJSON a package or secret. Merge
# conflicts and diagnostics both hit arbitrary unit/scalar values, so this is
# one helper instead of two guards drifting apart.
{ lib }:
let
  isDerivation = v: builtins.isAttrs v && (v.type or null) == "derivation";
in
{
  # renders v for an error message, falling back to a placeholder when v is a
  # derivation or fails to serialize (a function, or an attrset with a field
  # that throws on read -- the shape a secret-backed value can take). tryEval
  # catches that throw instead of letting it escape as an unrelated crash.
  safeRender =
    v:
    if isDerivation v then
      "<derivation ${v.name or "?"}>"
    else if builtins.isFunction v then
      "<function>"
    else
      let
        r = builtins.tryEval (builtins.toJSON v);
      in
      if r.success then r.value else "<unrenderable value>";

  # structural-only identification: attribute names of an attrset, never its
  # values. attrNames doesn't force what a key points to, so this stays safe
  # even when a value underneath is a derivation or throws when read -- it
  # never gets touched.
  safeShape =
    v:
    if isDerivation v then
      "<derivation ${v.name or "?"}>"
    else if builtins.isAttrs v then
      "{ ${lib.concatStringsSep ", " (builtins.sort (a: b: a < b) (builtins.attrNames v))} }"
    else
      "<${builtins.typeOf v}>";
}
