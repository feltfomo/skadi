{ lib }:
let
  invalid =
    field: expected: value:
    throw "axiom: canonical ${field} must be ${expected}; got ${builtins.typeOf value}";

  join =
    separator: parts:
    if !builtins.isString separator then
      invalid "separator" "a string" separator
    else if !builtins.isList parts || !lib.all builtins.isString parts then
      invalid "parts" "a list of strings" parts
    else if builtins.any (part: part == "") parts then
      throw "axiom: canonical parts must not be empty"
    else
      lib.concatStringsSep separator parts;

  qualified =
    {
      namespace,
      name,
      separator ? "/",
    }:
    join separator [
      namespace
      name
    ];

  path = join "/";
in
{
  inherit join qualified path;
}
