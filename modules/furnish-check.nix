{
  den,
  lib,
  resolve,
  resolveSystem,
  ...
}:
let
  denLib = import ./_lib/den.nix { inherit den lib; };
  tests = import ./_lib/furnish/tests.nix {
    inherit
      lib
      resolve
      resolveSystem
      ;
    principalContexts = denLib.hostPrincipals {
      system = "x86_64-linux";
      host = "khion";
    };
  };
in
{
  perSystem =
    { pkgs, system, ... }:
    let
      coordinator = pkgs.rustPlatform.buildRustPackage {
        pname = "furnish-coordinator";
        version = "0.1.0";
        src = ./_lib/furnish/coordinator;
        cargoLock.lockFile = ./_lib/furnish/coordinator/Cargo.lock;
      };
      runtimeSmoke =
        pkgs.runCommandLocal "furnish-runtime-smoke"
          {
            nativeBuildInputs = [
              coordinator
              pkgs.jq
            ];
          }
          ''
            # There's no /run/lock in the sandbox, so anything past the host lock is
            # unreachable from here. That leaves the executor primitive and the checks
            # that run before the lock is taken; the composed behavior lives in the
            # Rust tests and the VM matrix.
            parent="$TMPDIR/parent"
            mkdir -p "$parent"
            target="$TMPDIR/target"
            printf 'desired\n' > "$target"
            exec 9<"$parent"
            furnish-coordinator stage-native-symlink --parent-fd 9 --name value --target "$target"
            exec 9<&-
            test -L "$parent/value"
            test "$(readlink "$parent/value")" = "$target"

            # Validation runs before the lock bootstrap, so these have to come back
            # with a null cause. A cause would mean the run got past validation and
            # died on the lock instead, which would make the assertion a lie.
            base="$TMPDIR/base.json"
            jq -n '{
              schemaVersion:1,
              diagnosticContract:{
                schemaVersion:1,
                codes:{
                  invalidManifest:"runtime/invalid-manifest",
                  unsupportedExecutor:"runtime/unsupported-executor",
                  invalidDestination:"runtime/invalid-destination",
                  parentTraversal:"runtime/parent-traversal",
                  conflictingDestination:"runtime/conflicting-destination",
                  executorFailed:"runtime/executor-failed",
                  stagingVerification:"runtime/staging-verification",
                  publishRace:"runtime/publish-race",
                  finalVerification:"runtime/final-verification",
                  ledgerUnreadable:"runtime/ledger-unreadable",
                  ledgerInvalid:"runtime/ledger-invalid",
                  ledgerWriteFailed:"runtime/ledger-write-failed",
                  repairVerification:"runtime/repair-verification",
                  unresolvableDesiredTarget:"runtime/unresolvable-desired-target"
                }
              },
              entries:[{
                schemaVersion:1,
                filesystemIdentity:{namespace:"test",destination:"/managed/value",canonical:"test:/managed/value"},
                authority:{scope:"system",identity:"test/system"},
                managedRoot:"/managed",
                representation:"symlink",
                retainedArtifactTarget:"/target",
                executor:{identity:"furnish/native-symlink",protocolVersion:1},
                cleanupStrategy:"exact-symlink-target",
                selfHealStrategy:"exact-symlink-target",
                provenance:{declaration:"runtime-smoke",source:"modules/furnish-check.nix"}
              }]
            }' > "$base"

            # The five ledger and repair codes above are carried by the fixture
            # but are not exercised here, and cannot be: DiagnosticCodes fields
            # are non-optional, so a fixture missing any code fails manifest
            # deserialization before any assertion runs, while the codes
            # themselves are only reachable after the host lock is held, which
            # this sandbox has no /run/lock to provide.
            manifest="$TMPDIR/manifest.json"
            diagnostic="$TMPDIR/diagnostic.json"
            # --state-dir is passed even though validation never reaches the
            # ledger: the smoke should exercise the same argument surface the
            # systemd unit uses, or it stops being a check of the real invocation.
            expect_precheck() {
              jq "$2" "$base" > "$manifest"
              if furnish-coordinator reconcile \
                --manifest "$manifest" \
                --lock-name furnish-smoke.lock \
                --state-dir "$TMPDIR/state" \
                --setpriv ${pkgs.util-linux}/bin/setpriv 2> "$diagnostic"; then
                echo "invalid manifest unexpectedly accepted: $1" >&2
                exit 1
              fi
              # A bare `jq -e` exit 4 says only that something did not match, with
              # an empty build log to read it from. Print what was actually
              # emitted so the next failure is legible on the first look.
              if ! jq -e --arg code "$1" \
                'select(.schemaVersion==1 and .code==$code and .cause==null)' \
                "$diagnostic" >/dev/null; then
                echo "expected $1 with a null cause, got:" >&2
                cat "$diagnostic" >&2
                exit 1
              fi
            }

            # unsupported executor tuple
            expect_precheck "runtime/unsupported-executor" '.entries[0].executor.identity="furnish/bogus"'
            # bad manifest schema version
            expect_precheck "runtime/invalid-manifest" '.schemaVersion=2'
            # non-exact lifecycle strategy
            expect_precheck "runtime/invalid-manifest" '.entries[0].cleanupStrategy="copy"'
            # bad authority scope
            expect_precheck "runtime/invalid-manifest" '.entries[0].authority.scope="root"'
            # non-canonical filesystem identity
            expect_precheck "runtime/invalid-manifest" '.entries[0].filesystemIdentity.canonical="test:/wrong"'

            touch "$out"
          '';
    in
    {
      checks = {
        furnish-pure = pkgs.runCommandLocal "furnish-pure-tests" { } (
          assert tests.ok;
          "touch $out"
        );
        furnish-coordinator = coordinator;
        furnish-runtime = runtimeSmoke;
      };
      legacyPackages = lib.optionalAttrs (system == "x86_64-linux") {
        furnishCollisionEvidence = tests.collisionEvidence;
      };
    };
}
