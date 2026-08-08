{ lib }:
let
  invalid =
    field: expected: value:
    throw "axiom: identity ${field} must be ${expected}; got ${builtins.typeOf value}";

  mk =
    args@{
      label ? null,
      source ? null,
      path ? [ ],
    }:
    let
      unknown = builtins.filter (
        name:
        !(builtins.elem name [
          "label"
          "source"
          "path"
        ])
      ) (builtins.attrNames args);
    in
    if unknown != [ ] then
      throw "axiom: identity received unknown fields ${lib.concatStringsSep ", " unknown}"
    else if label != null && !builtins.isString label then
      invalid "label" "a string or null" label
    else if source != null && !builtins.isString source then
      invalid "source" "a string or null" source
    else if !builtins.isList path || !lib.all builtins.isString path then
      invalid "path" "a list of strings" path
    else
      {
        inherit label source path;
      };

  primary =
    identity:
    if !builtins.isAttrs identity then
      invalid "record" "an attribute set" identity
    else if (identity.label or null) != null then
      {
        kind = "label";
        value = identity.label;
      }
    else if (identity.source or null) != null then
      {
        kind = "source";
        value = identity.source;
      }
    else if (identity.path or [ ]) != [ ] then
      {
        kind = "path";
        value = identity.path;
      }
    else
      null;

  render =
    {
      identity,
      renderLabel,
      renderSource,
      renderPath,
      fallback,
    }:
    let
      selected = primary identity;
      renderer =
        if selected == null then
          null
        else if selected.kind == "label" then
          renderLabel
        else if selected.kind == "source" then
          renderSource
        else
          renderPath;
    in
    if !builtins.isFunction renderLabel then
      invalid "label renderer" "a function" renderLabel
    else if !builtins.isFunction renderSource then
      invalid "source renderer" "a function" renderSource
    else if !builtins.isFunction renderPath then
      invalid "path renderer" "a function" renderPath
    else if renderer == null then
      fallback
    else
      renderer selected.value;
in
{
  inherit mk primary render;
}
