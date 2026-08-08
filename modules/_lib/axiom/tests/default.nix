{ lib }:
let
  axiom = import ../default.nix { inherit lib; };
  inherit (axiom)
    validation
    schema
    identity
    requirements
    registry
    canonical
    phases
    tagged
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

  sampleSchema = schema.compile {
    fields = {
      count = {
        default = 1;
        validate = builtins.isInt;
        normalize = value: value + 1;
        onInvalid = _record: _value: "invalid-count";
      };
      name = {
        required = true;
        validate = builtins.isString;
        normalize = value: "normalized-${value}";
        onMissing = _record: "missing-name";
        onInvalid = _record: _value: "invalid-name";
      };
      payload = { };
    };
    onRecord = _value: "invalid-record";
    onUnknown = name: _value: "unknown-${name}";
  };

  validSchemaResult = sampleSchema {
    name = "sample";
    payload = poison;
  };
  invalidSchemaResult = sampleSchema {
    count = "many";
    extra = poison;
  };

  registrySpec =
    registrations:
    registry.compile {
      inherit registrations;
      keyOf = registration: registration.name;
      diagnosticsFor =
        registration:
        if builtins.isAttrs registration && registration ? name && builtins.isString registration.name then
          [ ]
        else
          [ "malformed-registration" ];
      less =
        left: right:
        if left.priority == right.priority then
          builtins.lessThan left.name right.name
        else
          left.priority < right.priority;
      onDuplicate = name: _registrations: "duplicate-${name}";
    };
  compiledRegistry = registrySpec [
    {
      name = "second";
      priority = 20;
      implementation = poison;
    }
    {
      name = "first";
      priority = 10;
      implementation = poison;
    }
  ];

  requirementObservation = requirements.observe {
    required = [
      "base"
      "render"
    ];
    candidates = [
      {
        name = "disabled";
        enabled = false;
        provides = poison;
      }
      {
        name = "partial";
        enabled = true;
        provides = [ "base" ];
      }
      {
        name = "complete";
        enabled = true;
        provides = [
          "render"
          "base"
        ];
      }
    ];
    enabled = candidate: candidate.enabled;
    providedBy = candidate: candidate.provides;
  };

  phaseSpec =
    registrations:
    phases.compile {
      names = [
        "prepare"
        "apply"
      ];
      inherit registrations;
      phaseOf =
        registration:
        if
          builtins.isAttrs registration && registration ? phase && builtins.isString registration.phase
        then
          registration.phase
        else
          null;
      runnable =
        registration:
        builtins.isAttrs registration && registration ? run && builtins.isFunction registration.run;
      onUnknown = _registration: phase: if phase == null then "unknown-missing" else "unknown-${phase}";
      onInvalid = _registration: phase: "invalid-${phase}";
    };
  compiledPhases = phaseSpec [
    {
      name = "apply";
      phase = "apply";
      run = _value: poison;
    }
    {
      name = "prepare-first";
      phase = "prepare";
      run = _value: poison;
    }
    {
      name = "prepare-second";
      phase = "prepare";
      run = _value: poison;
    }
  ];

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
    {
      name = "schema normalizes declared fields without forcing payloads";
      pass =
        validSchemaResult.diagnostics == [ ]
        && validSchemaResult.value.name == "normalized-sample"
        && validSchemaResult.value.count == 2;
    }
    {
      name = "schema accumulates unknown invalid and missing diagnostics";
      pass =
        invalidSchemaResult.diagnostics == [
          "unknown-extra"
          "invalid-count"
          "missing-name"
        ];
    }
    {
      name = "registry ordering and lookup leave implementations lazy";
      pass =
        compiledRegistry.value.keys == [
          "first"
          "second"
        ]
        && (compiledRegistry.value.lookup "second").name == "second";
    }
    {
      name = "registry duplicate diagnostics are caller-owned";
      pass =
        (registrySpec [
          {
            name = "same";
            priority = 1;
          }
          {
            name = "same";
            priority = 2;
          }
        ]).diagnostics == [ "duplicate-same" ];
    }
    {
      name = "registry validation and duplicates accumulate without keying malformed entries";
      pass =
        (registrySpec [
          { priority = 0; }
          {
            name = "same";
            priority = 1;
          }
          {
            name = "same";
            priority = 2;
          }
        ]).diagnostics == [
          "malformed-registration"
          "duplicate-same"
        ];
    }
    {
      name = "requirements qualify complete enabled candidates";
      pass =
        map (entry: entry.candidate.name) requirementObservation.qualified == [ "complete" ]
        &&
          map (entry: entry.candidate.name) requirementObservation.rejected == [
            "disabled"
            "partial"
          ]
        && (builtins.elemAt requirementObservation.rejected 1).missing == [ "render" ];
    }
    {
      name = "phases group registrations in declared phase order";
      pass =
        map (registration: registration.name) (compiledPhases.value.for "prepare") == [
          "prepare-first"
          "prepare-second"
        ]
        && map (registration: registration.name) (compiledPhases.value.for "apply") == [ "apply" ];
    }
    {
      name = "phases accumulate caller-owned boundary diagnostics";
      pass =
        (phaseSpec [
          { phase = "apply"; }
          { phase = "unknown"; }
        ]).diagnostics == [
          "unknown-unknown"
          "invalid-apply"
        ];
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
