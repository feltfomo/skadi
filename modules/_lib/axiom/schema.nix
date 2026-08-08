{ lib, validation }:
let
  invalid =
    field: expected: value:
    throw "axiom: schema ${field} must be ${expected}; got ${builtins.typeOf value}";

  validateField =
    name: field:
    if !builtins.isAttrs field then
      invalid "field '${name}'" "an attribute set" field
    else if field ? required && !builtins.isBool field.required then
      invalid "field '${name}'.required" "a boolean" field.required
    else if field ? validate && !builtins.isFunction field.validate then
      invalid "field '${name}'.validate" "a function" field.validate
    else if field ? normalize && !builtins.isFunction field.normalize then
      invalid "field '${name}'.normalize" "a function" field.normalize
    else if (field.required or false) && !(field ? default) && !(field ? onMissing) then
      throw "axiom: required schema field '${name}' must provide onMissing or a default"
    else if field ? onMissing && !builtins.isFunction field.onMissing then
      invalid "field '${name}'.onMissing" "a function" field.onMissing
    else if field ? onInvalid && !builtins.isFunction field.onInvalid then
      invalid "field '${name}'.onInvalid" "a function" field.onInvalid
    else
      field;

  compile =
    spec@{
      fields,
      onRecord,
      allowUnknown ? false,
      onUnknown ? null,
      order ? null,
    }:
    let
      unknownSpecFields = builtins.filter (
        name:
        !(builtins.elem name [
          "fields"
          "onRecord"
          "allowUnknown"
          "onUnknown"
          "order"
        ])
      ) (builtins.attrNames spec);
      checkedFields = lib.mapAttrs validateField fields;
      declaredNames = builtins.attrNames checkedFields;
      fieldNames = if order == null then declaredNames else order;
      checked =
        if unknownSpecFields != [ ] then
          throw "axiom: schema received unknown fields ${lib.concatStringsSep ", " unknownSpecFields}"
        else if !builtins.isAttrs fields then
          invalid "fields" "an attribute set" fields
        else if order != null && (!builtins.isList order || !lib.all builtins.isString order) then
          invalid "order" "a list of strings or null" order
        else if lib.unique fieldNames != fieldNames then
          throw "axiom: schema field order must be unique"
        else if builtins.sort builtins.lessThan fieldNames != declaredNames then
          throw "axiom: schema field order must name every declared field exactly once"
        else if !builtins.isFunction onRecord then
          invalid "onRecord" "a function" onRecord
        else if !builtins.isBool allowUnknown then
          invalid "allowUnknown" "a boolean" allowUnknown
        else if onUnknown != null && !builtins.isFunction onUnknown then
          invalid "onUnknown" "a function or null" onUnknown
        else if !allowUnknown && onUnknown == null then
          throw "axiom: closed schemas must provide onUnknown"
        else
          builtins.deepSeq (lib.mapAttrs (_name: field: builtins.seq field true) checkedFields) true;

      validateRecord =
        record:
        builtins.seq checked (
          if !builtins.isAttrs record then
            validation.failure [ (onRecord record) ]
          else
            let
              unknownNames = builtins.filter (name: !(builtins.elem name fieldNames)) (builtins.attrNames record);
              unknownDiagnostics =
                if allowUnknown then [ ] else map (name: onUnknown name record.${name}) unknownNames;
              fieldResults = map (
                name:
                let
                  field = checkedFields.${name};
                  present = builtins.hasAttr name record;
                  validator = field.validate or (_value: true);
                  normalize = field.normalize or (value: value);
                  result =
                    if present then
                      let
                        value = record.${name};
                      in
                      if validator value then
                        validation.success {
                          inherit name;
                          present = true;
                          value = normalize value;
                        }
                      else if field ? onInvalid then
                        validation.failure [ (field.onInvalid record value) ]
                      else
                        throw "axiom: schema field '${name}' rejected a value without onInvalid"
                    else if field ? default then
                      let
                        value = field.default;
                      in
                      if validator value then
                        validation.success {
                          inherit name;
                          present = true;
                          value = normalize value;
                        }
                      else if field ? onInvalid then
                        validation.failure [ (field.onInvalid record value) ]
                      else
                        throw "axiom: schema field '${name}' rejected its default without onInvalid"
                    else if field.required or false then
                      validation.failure [ (field.onMissing record) ]
                    else
                      validation.success {
                        inherit name;
                        present = false;
                      };
                in
                result
              ) fieldNames;
              diagnostics = validation.collect (
                [ unknownDiagnostics ] ++ map (result: result.diagnostics) fieldResults
              );
              normalizedFields = builtins.listToAttrs (
                builtins.concatMap (
                  result:
                  if result.diagnostics != [ ] || !result.value.present then
                    [ ]
                  else
                    [
                      {
                        inherit (result.value) name value;
                      }
                    ]
                ) fieldResults
              );
              normalized = if allowUnknown then record // normalizedFields else normalizedFields;
            in
            validation.fromDiagnostics diagnostics normalized
        );
    in
    validateRecord;
in
{
  inherit compile;
}
