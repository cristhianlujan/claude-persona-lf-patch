# S36 WP4 — Adversarial / Agent Security Assurance

## Boundary

This lane owns S36 WP4 adversarial and agent-security assurance end to end. It must not repair owner semantics, activate runtime/production/Golden, touch Cards I8 promotion, or claim S36 completeness. It creates no parallel test matrix or platform.

Canonical matrix/store policy: `S36_CANONICAL_LF_TEST_MATRIX` backed by the existing `lf_test_suites`, `lf_test_suite_cases`, `lf_test_runs`, `lf_test_assertion_results`, `lf_test_artifacts`, and `lf_test_requirement_bindings` stores.

## Adversarial inventory

| Attack family | Existing reusable harness | WP4 disposition |
| --- | --- | --- |
| Provenance spoofing / fake refs / hash mismatch | `profiles/evidence_lineage_reviewer_lf/evals/lineage_adversarial.py`; `profiles/quality_pack/evals/quality_gate_adversarial.py` | REUSE_EXISTING |
| Malformed evidence | `profiles/evidence_lineage_reviewer_lf/evals/lineage_adversarial.py`; `profiles/quality_pack/evals/quality_gate_adversarial.py` | REUSE_EXISTING |
| Stale/currentness attacks | `sandbox/lf_contract_gate_test/s30_currentness_cutover/test_s31_currentness_cutover.py`; lineage stale-reference case | REUSE_EXISTING |
| Receipt replay | `profiles/evidence_lineage_reviewer_lf/evals/lineage_adversarial.py` | REUSE_EXISTING |
| Idempotency/replay abuse | `sandbox/lf_contract_gate_test/s30_d_final_r09/test_s30d_c05_preparation.py` | REUSE_EXISTING |
| Route/orchestrator bypass | quality-pack and evidence-lineage routing adversarial cases | REUSE_EXISTING |
| Required-step bypass | `skills/profile_creator/evals/profile_operation_common_recorder_contract.py` proves owner-specific prior-step/evidence enforcement | PARTIAL_OWNER_SPECIFIC; transversal dynamic canary remains NOT_COVERED |
| Self-review / producer-as-reviewer | correlated-oracle checks existed, but no reusable execution-identity equality guard was located | GAP_FILLED_BY_WP4_GUARD |
| Authority escalation | owner-specific server-trust/self-attestation protections existed, but no reusable requested-vs-granted authority guard was located | GAP_FILLED_BY_WP4_GUARD |
| Invalid state transition | table-driven lifecycle controls exist in owner suites | PARTIAL_OWNER_SPECIFIC; owner-neutral negative transition canary remains NOT_COVERED |

## New reusable guard

`./s36_wp4_identity_authority_guard.py` is owner-agnostic and fail-closed. It tests only transversal authority and independent-review invariants. It does not interpret or repair owner semantics.

## Deterministic execution evidence

Command:

```text
python sandbox/lf_contract_gate_test/s36_wp4_adversarial/test_s36_wp4_identity_authority_guard.py
```

Observed producer result before source-first split:

```text
S36_WP4_IDENTITY_AUTHORITY_EXECUTED=1 TEST_COUNT=6 RESULT=PASS
```

## Explicit open coverage states

| Coverage item | State | Reason |
| --- | --- | --- |
| REQUIRED_STEP_BYPASS_TRANSVERSAL_DYNAMIC | NOT_COVERED | Existing proof is owner-specific; WP4 does not invent a generic owner semantic model. |
| INVALID_STATE_TRANSITION_TRANSVERSAL_NEGATIVE | NOT_COVERED | Existing lifecycle suites are owner-specific; no safe owner-neutral dynamic transition target is established. |
| LIVE_DESTRUCTIVE_AUTHORITY_ESCALATION | BLOCKED | WP4 permits sandbox/read-only/fail-closed tests only; runtime/production privilege attacks are not authorized. |

## Result-class discipline

`PASS` proves only the executed invariant. `FAIL` means observed invariant violation. `BLOCK` means an applicable test cannot safely or validly proceed. `NOT_COVERED` is an explicit missing assurance surface. A confirmed owner defect must be returned to the owner and preserved as a regression until explicit supersession; WP4 must not modify the owner implementation to make the test pass.
