{ lib, validation }:
let
  invalid =
    field: expected: value:
    throw "axiom: phases ${field} must be ${expected}; got ${builtins.typeOf value}";

  compile =
    {
      names,
      registrations,
      phaseOf,
      runnable,
      onUnknown,
      onInvalid,
    }:
    if !builtins.isList names || !lib.all builtins.isString names then
      invalid "names" "a list of strings" names
    else if lib.unique names != names then
      throw "axiom: phase names must be unique"
    else if !builtins.isList registrations then
      invalid "registrations" "a list" registrations
    else if !builtins.isFunction phaseOf then
      invalid "phaseOf" "a function" phaseOf
    else if !builtins.isFunction runnable then
      invalid "runnable" "a function" runnable
    else if !builtins.isFunction onUnknown then
      invalid "onUnknown" "a function" onUnknown
    else if !builtins.isFunction onInvalid then
      invalid "onInvalid" "a function" onInvalid
    else
      let
        inspected = map (
          registration:
          let
            phase = phaseOf registration;
            known = builtins.isString phase && builtins.elem phase names;
            valid = known && runnable registration;
          in
          {
            inherit
              registration
              phase
              known
              valid
              ;
          }
        ) registrations;
        unknownDiagnostics = map (entry: onUnknown entry.registration entry.phase) (
          builtins.filter (entry: !entry.known) inspected
        );
        invalidDiagnostics = map (entry: onInvalid entry.registration entry.phase) (
          builtins.filter (entry: entry.known && !entry.valid) inspected
        );
        diagnostics = unknownDiagnostics ++ invalidDiagnostics;
        byName = lib.genAttrs names (
          name:
          map (entry: entry.registration) (
            builtins.filter (entry: entry.valid && entry.phase == name) inspected
          )
        );
        compiled = {
          order = names;
          inherit registrations byName;
          for =
            name:
            if builtins.elem name names then
              byName.${name}
            else
              throw "axiom: unknown compiled phase '${name}'";
        };
      in
      validation.fromDiagnostics diagnostics compiled;
in
{
  inherit compile;
}
