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
            # The unprivileged Nix sandbox has no /run/lock, so the full reconcile
            # path (which acquires the host-global advisory lock before touching any
            # entry) cannot run here. This smoke covers the two reconciliation
            # surfaces that are observable without the lock:
            #   (a) the native-symlink executor primitive (stage-native-symlink);
            #   (b) pre-lock manifest validation via reconcile against invalid input.
            # The composed reconcile_entry semantics (foreign refusal, idempotency,
            # path-safety) are covered by the coordinator Rust unit tests; the full
            # end-to-end publish path is covered by the VM matrix + the real-host test.

            # (a) Native-symlink executor primitive (lock-free). stage-native-symlink
            # stages a symlink at an inherited parent-directory fd.
            parent="$TMPDIR/parent"
            mkdir -p "$parent"
            target="$TMPDIR/target"
            printf 'desired\n' > "$target"
            exec 9<"$parent"
            furnish-coordinator stage-native-symlink --parent-fd 9 --name value --target "$target"
            exec 9<&-
            test -L "$parent/value"
            test "$(readlink "$parent/value")" = "$target"

            # (b) Pre-lock manifest validation. validate_manifest runs before the
            # /run/lock bootstrap, so a manifest that trips a validation guard must
            # fail with the contracted diagnostic code and a null cause (i.e. it never
            # reached the lock, whose failure carries a non-null syscall cause).
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
                  finalVerification:"runtime/final-verification"
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

            manifest="$TMPDIR/manifest.json"
            diagnostic="$TMPDIR/diagnostic.json"
            expect_precheck() {
              jq "$2" "$base" > "$manifest"
              if furnish-coordinator reconcile \
                --manifest "$manifest" \
                --lock-name furnish-smoke.lock \
                --setpriv ${pkgs.util-linux}/bin/setpriv 2> "$diagnostic"; then
                echo "invalid manifest unexpectedly accepted: $1" >&2
                exit 1
              fi
              jq -e --arg code "$1" \
                'select(.schemaVersion==1 and .code==$code and .cause==null)' \
                "$diagnostic" >/dev/null
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
