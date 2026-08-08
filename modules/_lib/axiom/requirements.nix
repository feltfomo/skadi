{ lib }:
let
  invalid =
    field: expected: value:
    throw "axiom: requirements ${field} must be ${expected}; got ${builtins.typeOf value}";

  normalize =
    values:
    if !builtins.isList values || !lib.all builtins.isString values then
      invalid "values" "a list of strings" values
    else
      lib.unique values;

  evaluate =
    required: provided:
    let
      required' = normalize required;
      provided' = normalize provided;
      missing = builtins.filter (item: !(builtins.elem item provided')) required';
    in
    {
      required = required';
      provided = provided';
      inherit missing;
      satisfied = missing == [ ];
    };

  observe =
    {
      required,
      candidates,
      providedBy,
      enabled ? (_candidate: true),
    }:
    if !builtins.isList candidates then
      invalid "candidates" "a list" candidates
    else if !builtins.isFunction providedBy then
      invalid "providedBy" "a function" providedBy
    else if !builtins.isFunction enabled then
      invalid "enabled" "a function" enabled
    else
      let
        entries = map (
          candidate:
          let
            active = enabled candidate;
            result = if active then evaluate required (providedBy candidate) else null;
          in
          {
            inherit candidate;
            enabled = active;
            required = normalize required;
            provided = if active then result.provided else [ ];
            missing = if active then result.missing else normalize required;
            satisfied = active && result.satisfied;
          }
        ) candidates;
      in
      {
        inherit entries;
        qualified = builtins.filter (entry: entry.satisfied) entries;
        rejected = builtins.filter (entry: !entry.satisfied) entries;
      };
in
{
  inherit normalize evaluate observe;
}
