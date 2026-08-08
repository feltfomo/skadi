{ lib }:
let
  invalid =
    field: expected: value:
    throw "axiom: validation ${field} must be ${expected}; got ${builtins.typeOf value}";

  validateDiagnostics =
    diagnostics:
    if builtins.isList diagnostics then diagnostics else invalid "diagnostics" "a list" diagnostics;

  validateResult =
    result:
    if !builtins.isAttrs result then
      invalid "result" "an attribute set" result
    else if !(result ? diagnostics) then
      throw "axiom: validation result is missing diagnostics"
    else
      let
        diagnostics = validateDiagnostics result.diagnostics;
      in
      if diagnostics == [ ] && !(result ? value) then
        throw "axiom: successful validation result is missing a value"
      else
        result;

  success = value: {
    diagnostics = [ ];
    inherit value;
  };

  failure = diagnostics: {
    diagnostics = validateDiagnostics diagnostics;
  };

  fromDiagnostics =
    diagnostics: value: if diagnostics == [ ] then success value else failure diagnostics;

  isSuccess =
    result:
    let
      checked = validateResult result;
    in
    checked.diagnostics == [ ];

  mapResult =
    f: result:
    if !builtins.isFunction f then
      invalid "map function" "a function" f
    else
      let
        checked = validateResult result;
      in
      if checked.diagnostics == [ ] then success (f checked.value) else failure checked.diagnostics;

  collect =
    groups:
    if !builtins.isList groups || !lib.all builtins.isList groups then
      invalid "groups" "a list of lists" groups
    else
      builtins.concatLists groups;

  map2 =
    f: left: right:
    if !builtins.isFunction f then
      invalid "map2 function" "a function" f
    else
      let
        checkedLeft = validateResult left;
        checkedRight = validateResult right;
        diagnostics = collect [
          checkedLeft.diagnostics
          checkedRight.diagnostics
        ];
      in
      if diagnostics == [ ] then
        success (f checkedLeft.value checkedRight.value)
      else
        failure diagnostics;

  sequence =
    results:
    if !builtins.isList results then
      invalid "results" "a list" results
    else
      let
        checked = map validateResult results;
        diagnostics = collect (map (result: result.diagnostics) checked);
      in
      if diagnostics == [ ] then success (map (result: result.value) checked) else failure diagnostics;

  traverse = f: values: sequence (map f values);

  optional =
    condition: diagnostic:
    if !builtins.isBool condition then
      invalid "condition" "a boolean" condition
    else
      lib.optional condition diagnostic;

  finish =
    fail: result:
    if !builtins.isFunction fail then
      invalid "failure handler" "a function" fail
    else
      let
        checked = validateResult result;
      in
      if checked.diagnostics == [ ] then checked.value else fail checked.diagnostics;
in
{
  inherit
    success
    failure
    fromDiagnostics
    isSuccess
    map2
    sequence
    traverse
    collect
    optional
    finish
    ;
  map = mapResult;
}
