# PACK_VALIDATION_HARNESS_V1

Capability candidate for deterministic, externally governed validation of LF profile packs.

## Scope

This capability does not replace profile-domain validators. It makes them observable and non-authoritative for their own certification.

The harness:

1. receives the governed profile inventory as external JSON;
2. receives the versioned validation-floor policy snapshot as external JSON;
3. reconciles inventory and `profiles/*`;
4. resolves enforcement state only from the external policy;
5. executes the profile-local validator as a subprocess;
6. executes the profile adversarial suite directly, without delegating the verdict to `validate_pack.py`;
7. executes an external holdout owned under this capability for every `ENFORCED` profile;
8. computes validator, suite, holdout and execution-result SHA-256 itself;
9. emits one canonical result envelope;
10. never authorizes runtime or automatic impact.

## Six invariants

1. The producer does not control the external floor.
2. The producer does not provide the authoritative cryptographic evidence of PASS.
3. The producer cannot self-exclude from enforcement.
4. The producer-local validator is not the execution authority for the adversarial evidence.
5. Pack existence is reconciled against governed inventory, not inferred only from the filesystem.
6. An ENFORCED producer does not control all certification cases; an external holdout is mandatory.

## Authority boundaries

- Floor values and enforcement state: expected from `POL-PACK-VALIDATION-FLOOR` through the Supabase policy snapshot boundary.
- Profile existence: expected from the governed profile inventory (currently `public.lf_activos` readback prepared by the CI consumer).
- Profile implementation: `profiles/<slug>/**`.
- External holdouts: `sandbox/lf_contract_gate_test/pack_validation_harness/holdouts/**`.
- Canonical result contract: `sandbox/lf_contract_gate_test/pack_validation_harness/schemas/pack_validation_result.schema.json`.
- Floor shape contract: `sandbox/lf_contract_gate_test/pack_validation_harness/schemas/pack_validation_floor.schema.json`.

A profile-local `manifest.json` may request a stricter `min_profile_cases`, but cannot lower the external floor. A manifest field that claims `NOT_ENFORCED` has no authority; enforcement is resolved only from the external policy snapshot.

## Fail-closed behavior

The harness blocks when:

- a disk profile has no governed inventory row;
- an inventory profile is missing on disk unless the external policy explicitly records a governed `NOT_ENFORCED` exception with missing-materialization allowance;
- an ENFORCED profile lacks an external floor entry, local validator, declared adversarial suite, thresholds, or external holdout;
- a profile threshold is lower than the external floor;
- a suite/holdout times out, exits non-zero, emits malformed JSON, reports `passed=false`, or has too few cases;
- a declared path escapes its owner boundary or is a symlink;
- required policy invariants are disabled.

## Rollout boundary

This source-only PR is intentionally not the authority cutover and follows the existing two-stage capability precedent: versioned source first; governed registration/binding later.

Before productive CI enforcement:

1. materialize `POL-PACK-VALIDATION-FLOOR` as a versioned/hash-bound Supabase policy;
2. bind it to the governed profile creation/update operations;
3. provide explicit externally governed states for the current profile inventory;
4. add independent holdouts for each profile promoted to `ENFORCED`;
5. then replace fragmented profile validation authority with this harness in a separate cutover.

Until that authority exists, CI runs only this capability's regression suite. No profile is silently promoted by this candidate.

## Self-test

```bash
python sandbox/lf_contract_gate_test/pack_validation_harness/test_pack_validation_harness_v1.py
```

Expected: `PASS_PACK_VALIDATION_HARNESS_V1=11/11`.

## EKB consumed

- `CI-UNVERSIONED-GENERATED-ARTIFACT-CROSS-LANE-BLOCKER-001`: harness source is versioned and owner-scoped; generated evidence stays outside the validated source universe.
- `PROFILE-CREATOR-CUSTOMER-DEPTH-CONTRACT-003`: local pack PASS is not promoted to producer-depth or semantic approval.
- `PROFILE-RUNTIME-TRANSPORT-SUCCESS-QUALITY-001`: execution/transport success remains distinct from behavioral quality.

## No duplication

No shared imported validation core is introduced. Domain rules remain local. The shared surface is the externally validated contract and harness execution boundary.
