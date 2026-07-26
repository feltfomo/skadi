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
      mkCoordinator =
        {
          suffix ? "",
          features ? [ ],
        }:
        pkgs.rustPlatform.buildRustPackage {
          pname = "furnish-coordinator${suffix}";
          version = "0.1.0";
          src = ./_lib/furnish/coordinator;
          cargoLock.lockFile = ./_lib/furnish/coordinator/Cargo.lock;
          buildFeatures = features;
        };
      coordinator = mkCoordinator { };
      # the crash points exist only in this build. absence from the shipped one
      # is a compile-time property, which is the only kind worth asserting.
      coordinatorFaultInjection = mkCoordinator {
        suffix = "-fault-injection";
        features = [ "fault-injection" ];
      };
      faultInjectionBoundary =
        pkgs.runCommandLocal "furnish-fault-injection-boundary" { nativeBuildInputs = [ ]; }
          ''
            # both directions are checked. the packaged coordinator must not carry
            # the fault-point symbol and the test build must, or this passes against
            # a binary that never had the feature compiled either way.
            if grep -a -q FURNISH_FAULT_POINT ${coordinator}/bin/furnish-coordinator; then
              echo 'packaged coordinator contains the fault-injection symbol' >&2
              exit 1
            fi
            if ! grep -a -q FURNISH_FAULT_POINT ${coordinatorFaultInjection}/bin/furnish-coordinator; then
              echo 'fault-injection build is missing the fault-injection symbol' >&2
              exit 1
            fi
            touch "$out"
          '';
      runtimeSmoke =
        pkgs.runCommandLocal "furnish-runtime-smoke"
          {
            nativeBuildInputs = [
              coordinator
              pkgs.jq
            ];
          }
          ''
            # the nix build sandbox provides no /run/lock, and this invokes the
            # packaged binary with the arguments the systemd unit passes, so the
            # test-only --lock-dir seam stays out of reach here. what is left is the
            # executor primitive and the checks that run before the lock is taken.
            # composed behavior belongs to the rust tests and the vm matrix, where a
            # real lock directory exists.
            parent="$TMPDIR/parent"
            mkdir -p "$parent"
            target="$TMPDIR/target"
            printf 'desired\n' > "$target"
            exec 9<"$parent"
            furnish-coordinator stage-native-symlink --parent-fd 9 --name value --target "$target"
            exec 9<&-
            test -L "$parent/value"
            test "$(readlink "$parent/value")" = "$target"

            # validation runs before the lock bootstrap, so these have to come back
            # with a null cause. a cause would mean the run got past validation and
            # died on the lock instead.
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
                  unresolvableDesiredTarget:"runtime/unresolvable-desired-target",
                  contentVerification:"runtime/content-verification",
                  transitionRefused:"runtime/transition-refused",
                  unresolvedRetirement:"runtime/unresolved-retirement",
                  pendingRecovery:"runtime/pending-recovery"
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

            # the ledger, repair and writable-lifecycle codes in the fixture are not
            # exercised here and cannot be. DiagnosticCodes fields are non-optional,
            # so dropping any of them fails manifest deserialization before an
            # assertion runs, and the codes themselves need a held host lock, which
            # the nix build sandbox has nowhere to take.
            manifest="$TMPDIR/manifest.json"
            diagnostic="$TMPDIR/diagnostic.json"
            # --state-dir is passed even though validation never reaches the ledger,
            # because the argument surface here is the one the systemd unit uses.
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
              # a bare `jq -e` exit 4 says only that something did not match, with
              # an empty build log to read it from. print what was actually emitted
              # so the next failure is legible on the first look.
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
        furnish-coordinator-fault-injection = coordinatorFaultInjection;
        furnish-fault-injection-boundary = faultInjectionBoundary;
        furnish-runtime = runtimeSmoke;
      };
      legacyPackages = lib.optionalAttrs (system == "x86_64-linux") {
        furnishCollisionEvidence = tests.collisionEvidence;
      };
    };
}
