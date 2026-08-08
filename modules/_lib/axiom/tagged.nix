_:
let
  marker = "axiom/tagged";

  invalid =
    field: expected: value:
    throw "axiom: tagged ${field} must be ${expected}; got ${builtins.typeOf value}";

  validateTag =
    tag:
    if !builtins.isString tag then
      invalid "tag" "a string" tag
    else if tag == "" then
      throw "axiom: tagged tag must not be empty"
    else
      tag;

  mk = tag: value: {
    __axiom = marker;
    tag = validateTag tag;
    inherit value;
  };

  isTagged =
    value: builtins.isAttrs value && (value.__axiom or null) == marker && value ? tag && value ? value;

  tagOf = value: if isTagged value then value.tag else null;

  has = tag: value: isTagged value && value.tag == validateTag tag;

  expect =
    tag: value:
    if !isTagged value then
      throw "axiom: expected a tagged value"
    else if value.tag != validateTag tag then
      throw "axiom: expected tag '${tag}', got '${value.tag}'"
    else
      value.value;

  mapValue =
    f: value:
    if !builtins.isFunction f then
      invalid "map function" "a function" f
    else if !isTagged value then
      throw "axiom: expected a tagged value"
    else
      mk value.tag (f value.value);

  match =
    handlers: value:
    if !builtins.isAttrs handlers then
      invalid "handlers" "an attribute set" handlers
    else if !isTagged value then
      throw "axiom: expected a tagged value"
    else if builtins.hasAttr value.tag handlers then
      let
        handler = handlers.${value.tag};
      in
      if builtins.isFunction handler then
        handler value.value
      else
        invalid "handler '${value.tag}'" "a function" handler
    else if handlers ? default then
      if builtins.isFunction handlers.default then
        handlers.default value.tag value.value
      else
        invalid "default handler" "a function" handlers.default
    else
      throw "axiom: no handler for tag '${value.tag}'";
in
{
  inherit
    mk
    isTagged
    tagOf
    has
    expect
    match
    ;
  map = mapValue;
}
