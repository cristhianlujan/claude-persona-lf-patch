# R4 — validator_evidence readers

Read-only audit cut: 2026-10-06. This document classifies every current `programacion` function whose definition references `validator_evidence`, and sizes Input Governance run history logically with `pg_column_size` over the run, assessment, and proposal rows. No cleanup is authorized by this document.

## Reader classification

The hard boundary is whether the function directly reads `validator_evidence->'assertions'`. Six do and therefore require the complete assertion array. The other sixteen do not consume the assertion array; for retention they only need the validator result/integrity projection they actually inspect (outcome/hash and the small evidence metadata fields noted below), not the full assertion payload.

| Function | Class | Why |
|---|---|---|
| fn_guard_input_family_assessment_update | ASSERTIONS_COMPLETE | Validates the assertion array while accepting validator transition. |
| fn_guard_input_family_execution_update | ASSERTIONS_COMPLETE | Reads assertions while enforcing independent validator execution/evidence. |
| fn_guard_input_validator_semantic_coherence_v512 | ASSERTIONS_COMPLETE | Iterates assertions and checks semantic source/operator/expected coherence. |
| fn_input_auth006_build_assertions | ASSERTIONS_COMPLETE | Reuses and rebinds prior validator assertions. |
| fn_input_owner_decision_assertions | ASSERTIONS_COMPLETE | Iterates parent assertions and rebinds them to the new run. |
| fn_input_v58_build_assertions | ASSERTIONS_COMPLETE | Builds a new assertion set from parent validator assertions. |
| fn_guard_input_family_assessment_insert | HASH_OUTCOME | Rejects curator-side prevalidation; does not consume assertion bodies. |
| fn_guard_input_family_semantic_depth | HASH_OUTCOME | Checks semantic-depth evidence hash/projection on validator transition. |
| fn_guard_input_family_semantic_depth_v510 | HASH_OUTCOME | Same semantic-depth projection for v5.10 path. |
| fn_guard_input_gap_proposal_update_v512 | HASH_OUTCOME | Checks validator identity/outcome plus direct-source/snapshot evidence metadata. |
| fn_guard_input_readiness_run | HASH_OUTCOME | Requires full PASS universe and source-snapshot/identity consistency, not assertions. |
| fn_input_actionable_remediation_summary_v1 | HASH_OUTCOME | Carries validator evidence into remediation summary but does not inspect assertion array. |
| fn_input_governance_bootstrap_materialize_v1 | HASH_OUTCOME | Initializes validator fields as PENDING/empty; does not read assertions. |
| fn_input_governance_bootstrap_materialize_v2 | HASH_OUTCOME | Initializes validator fields as PENDING/empty; does not read assertions. |
| fn_input_governance_bootstrap_validate_v1 | HASH_OUTCOME | Produces validator evidence/outcome; assertion completeness is enforced through its assertion builder, not by reading stored assertion bodies here. |
| fn_input_governance_curator_rebind_v1 | HASH_OUTCOME | Copies/reset validator projection during curator successor/rebind; no assertion read. |
| fn_input_governance_execute | HASH_OUTCOME | Gates on PASS, validator identity, direct-source readback and snapshot consistency. |
| fn_input_governance_recurate_source_stale_v1 | HASH_OUTCOME | Creates successor assessments and resets validator projection. |
| fn_input_governance_recurate_v2 | HASH_OUTCOME | Creates recuration successor and resets validator projection. |
| fn_input_governance_validate_gap_proposals_v1 | HASH_OUTCOME | Writes PASS plus bounded source-readback metadata. |
| fn_input_governance_validate_v2 | HASH_OUTCOME | Produces validator evidence/outcome; does not read stored assertion bodies. |
| fn_input_governance_validator_rebind_v1 | HASH_OUTCOME | Writes rebound validator evidence after separate assertion-building call; does not read stored assertion bodies itself. |

Totals: **6 ASSERTIONS_COMPLETE**, **16 HASH_OUTCOME**.

"Hash/outcome" does not mean every one of these functions reads only two columns. Some also require bounded evidence metadata such as `source_snapshot_sha256`, `direct_source_readback`, `execution_id`, component/identity or semantic-depth hash. The retention conclusion is narrower: they do **not** require retaining the full `assertions` array.

## Run classification and logical footprint

Classification rule: `TEST_OR_PILOT` when `scope.mode` matches TEST/SHADOW/PROBE/SELFTEST/CANDIDATE/PILOT or `scope.pilot=true`; otherwise `CANONICAL_OR_RUNTIME`.

| Class | Runs | Invalidated | Non-invalidated | Run MiB | Assessment MiB | Proposal MiB | Total logical MiB |
|---|---:|---:|---:|---:|---:|---:|---:|
| TEST_OR_PILOT | 108 | 106 | 2 | 8.4389 | 43.3217 | 0.0298 | **51.7904** |
| CANONICAL_OR_RUNTIME | 127 | 76 | 51 | 5.9954 | 98.1633 | 5.8723 | **110.0310** |

These are logical row bytes from `pg_column_size`, not physical table/index/TOAST allocation. They are suitable for relative R4 attribution, not a claim about disk bytes reclaimed by VACUUM.

## Live pilot exclusion

Run **22** is explicitly excluded from any R4 retention/delete candidate set:

- `id=22`
- `version_id=12`
- `pantalla_id=51`
- `status=CURATING`
- `invalidated_at IS NULL`
- `scope.pilot=true`
- `supersedes_run_id=21`

Run 21 is also non-invalidated (`BLOCKED`, pilot=true) and is the immediate predecessor of run 22. R4 must not sever that live lineage while run 22 remains current/in progress. Therefore the 108 TEST_OR_PILOT rows are **not** equivalent to 108 purgeable rows: 106 are invalidated; 21/22 remain live lineage, with run 22 explicitly protected.

## R4 conclusion

Assertion-heavy retention can target historical evidence only after preserving the six ASSERTIONS_COMPLETE consumers' required lineage. For the sixteen HASH_OUTCOME consumers, a compact retained projection can omit full assertion bodies provided it preserves each function's bounded integrity fields. No canonical/runtime run or live pilot lineage is authorized for deletion by this analysis.
