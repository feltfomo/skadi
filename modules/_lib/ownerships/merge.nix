# _lib/ownerships/merge.nix
#
# The value-merge strategy table + conflict policy. mergeTwo is keyed by value
# SHAPE: attrsets deep-recurse (structural, not policy), lists go through a named
# strategy (ordered-concat by default to preserve source order; dedup-union
# available opt-in for set-like lists), scalars hit the conflict policy. New list
# strategies and new conflict policies (e.g. a future "owner wins / foreign
# write throws") register by passing a different table -- never by editing the
# fold.
{ lib }:
let
  inherit (builtins)
    isAttrs
    isList
    head
    tail
    foldl'
    ;

  # scalar conflict policy: equal survives, differ is a hard error. an alternative
  # owner-wins policy can land with the same signature.
  strictScalar =
    path: a: b:
    if a == b then
      a
    else
      throw "ownerships: conflict at ${
        if path == "" then "<root>" else path
      }: co-owners set differing values (${builtins.toJSON a} vs ${builtins.toJSON b})";

  # list strategies, looked up by name. a new strategy is a new table entry.
  builtinStrategies = {
    "ordered-concat" = a: b: a ++ b;
    "dedup-union" = a: b: lib.unique (a ++ b);
  };

  # build a pairwise merge from a strategy table keyed by value shape. attrset
  # recursion is structural; only the list strategy (per path) and the scalar
  # conflict are policy, so both are injectable without editing mergeTwo.
  mkMerge =
    {
      strategies ? builtinStrategies,
      listStrategyFor ? (_path: "ordered-concat"),
      conflictPolicy ? strictScalar,
    }:
    let
      mergeTwo =
        path: a: b:
        let
          sub = k: if path == "" then k else "${path}.${k}";
        in
        if isAttrs a && isAttrs b then
          lib.genAttrs (lib.attrNames (a // b)) (
            k: if (a ? ${k}) && (b ? ${k}) then mergeTwo (sub k) a.${k} b.${k} else a.${k} or b.${k}
          )
        else if isList a && isList b then
          let
            name = listStrategyFor path;
            strat = strategies.${name} or (throw "ownerships: no merge strategy '${name}' (at ${path})");
          in
          strat a b
        else
          conflictPolicy path a b;

      # a lone survivor passes through untouched; an empty survivor set is the
      # empty config.
      mergeAll = values: if values == [ ] then { } else foldl' (mergeTwo "") (head values) (tail values);
    in
    {
      inherit mergeTwo mergeAll;
    };
in
{
  inherit
    builtinStrategies
    strictScalar
    mkMerge
    ;
}
