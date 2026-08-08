{ lib, validation }:
let
  invalid =
    field: expected: value:
    throw "axiom: registry ${field} must be ${expected}; got ${builtins.typeOf value}";

  compile =
    {
      registrations,
      keyOf,
      diagnosticsFor ? (_registration: [ ]),
      less ? (left: right: builtins.lessThan (keyOf left) (keyOf right)),
      onDuplicate,
    }:
    if !builtins.isList registrations then
      invalid "registrations" "a list" registrations
    else if !builtins.isFunction keyOf then
      invalid "keyOf" "a function" keyOf
    else if !builtins.isFunction diagnosticsFor then
      invalid "diagnosticsFor" "a function" diagnosticsFor
    else if !builtins.isFunction less then
      invalid "less" "a function" less
    else if !builtins.isFunction onDuplicate then
      invalid "onDuplicate" "a function" onDuplicate
    else
      let
        checked = map (
          registration:
          let
            diagnostics = diagnosticsFor registration;
          in
          if !builtins.isList diagnostics then
            invalid "registration diagnostics" "a list" diagnostics
          else
            {
              inherit registration diagnostics;
            }
        ) registrations;
        valid = builtins.filter (entry: entry.diagnostics == [ ]) checked;
        keyed = map (entry: {
          key = keyOf entry.registration;
          inherit (entry) registration;
        }) valid;
        groups = lib.groupBy (entry: entry.key) keyed;
        duplicateKeys = builtins.filter (key: builtins.length groups.${key} > 1) (
          builtins.attrNames groups
        );
        diagnostics = validation.collect (
          map (entry: entry.diagnostics) checked
          ++ map (key: [ (onDuplicate key (map (entry: entry.registration) groups.${key})) ]) duplicateKeys
        );
        ordered = builtins.sort less registrations;
        byKey = builtins.listToAttrs (
          map (registration: {
            name = keyOf registration;
            value = registration;
          }) ordered
        );
        compiled = {
          inherit registrations ordered byKey;
          keys = map keyOf ordered;
          lookup = key: byKey.${key} or null;
          select = predicate: builtins.filter predicate ordered;
        };
      in
      validation.fromDiagnostics diagnostics compiled;
in
{
  inherit compile;
}
