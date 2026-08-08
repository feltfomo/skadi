{ lib }:
let
  axiom = import ../default.nix { inherit lib; };
  inherit (axiom)
    validation
    identity
    tagged
    canonical
    ;

  throws = value: !(builtins.tryEval value).success;
  poison = throw "forced poison";

  leftFailure = validation.failure [ "left" ];
  rightFailure = validation.failure [ "right" ];
  accumulated = validation.map2 (_left: _right: poison) leftFailure rightFailure;
  sequenced = validation.sequence [
    (validation.success 1)
    leftFailure
    rightFailure
  ];

  labeled = identity.mk {
    label = "unit";
    source = "modules/unit.nix";
  };
  sourced = identity.mk { source = "modules/unit.nix"; };
  anonymous = identity.mk { };
  renderIdentity =
    selected: fallback:
    identity.render {
      identity = selected;
      renderLabel = label: "label ${label}";
      renderSource = source: "source ${source}";
      renderPath = path: canonical.path path;
      inherit fallback;
    };

  selected = tagged.mk "selected" 4;

  cases = [
    {
      name = "validation maps successful values";
      pass = (validation.map (value: value + 1) (validation.success 1)).value == 2;
    }
    {
      name = "validation map preserves failures without forcing the mapper";
      pass = (validation.map (_value: poison) leftFailure).diagnostics == [ "left" ];
    }
    {
      name = "validation map2 accumulates failures in order";
      pass =
        accumulated.diagnostics == [
          "left"
          "right"
        ];
    }
    {
      name = "validation sequence accumulates without forcing successful payloads";
      pass =
        sequenced.diagnostics == [
          "left"
          "right"
        ];
    }
    {
      name = "validation finish delegates opaque failures";
      pass =
        validation.finish (diagnostics: diagnostics) accumulated == [
          "left"
          "right"
        ];
    }
    {
      name = "validation optional keeps diagnostics opaque";
      pass =
        validation.collect [
          (validation.optional true "problem")
          (validation.optional false poison)
        ] == [ "problem" ];
    }
    {
      name = "identity prefers labels over sources";
      pass =
        (identity.primary labeled) == {
          kind = "label";
          value = "unit";
        };
    }
    {
      name = "identity falls back from label to source";
      pass = renderIdentity sourced poison == "source modules/unit.nix";
    }
    {
      name = "identity leaves fallback rendering to the caller";
      pass = renderIdentity anonymous "fallback" == "fallback";
    }
    {
      name = "tagged values preserve their tag through maps";
      pass = tagged.expect "selected" (tagged.map (value: value + 1) selected) == 5;
    }
    {
      name = "tagged dispatch selects the named handler";
      pass =
        tagged.match {
          selected = value: value * 2;
          default = _tag: _value: poison;
        } selected == 8;
    }
    {
      name = "tagged dispatch has an explicit fallback";
      pass =
        tagged.match { default = tag: value: "${tag}:${toString value}"; } (tagged.mk "other" 3)
        == "other:3";
    }
    {
      name = "tagged expect rejects a different tag";
      pass = throws (tagged.expect "rejected" selected);
    }
    {
      name = "canonical joins validated parts";
      pass =
        canonical.join ":" [
          "home"
          ".config/example"
        ] == "home:.config/example";
    }
    {
      name = "canonical qualified names default to slash";
      pass =
        canonical.qualified {
          namespace = "x86_64-linux";
          name = "khion";
        } == "x86_64-linux/khion";
    }
    {
      name = "canonical rejects empty identity parts";
      pass = throws (
        canonical.path [
          ""
          "leaf"
        ]
      );
    }
  ];

  failing = builtins.filter (case: !case.pass) cases;
  ok =
    if failing == [ ] then
      true
    else
      throw "axiom tests FAILED: ${lib.concatMapStringsSep ", " (case: case.name) failing}";
in
{
  inherit cases ok;
}
