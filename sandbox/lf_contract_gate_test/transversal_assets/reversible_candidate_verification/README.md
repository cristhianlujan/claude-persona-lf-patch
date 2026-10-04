# REVERSIBLE_CANDIDATE_VERIFICATION v1.0.1

Owner: `SUPER_ADMIN`.

Public contract:

- candidate identity
- flow adapter
- baseline / oracle, including an `INDEPENDENT_ASSURANCE` receipt
- rollback contract

Output: deterministic `PASS` or `BLOCK` receipt. A receipt never grants promotion, activation, cutover, or production authority.

Mandatory invariants:

1. `ROLLBACK_ONLY` always.
2. Capture baseline state digest before candidate execution.
3. Execute candidate only through the supplied flow adapter.
4. Require the oracle to carry an exact-version `INDEPENDENT_ASSURANCE` receipt and fail closed if independence is missing, `UNPROVEN`, `NOT_INDEPENDENT`, stale, tampered, or dimensionally incomplete.
5. Evaluate the baseline/candidate observation through that separately supplied oracle.
6. Roll back exactly and compare post-rollback digest with the baseline digest.
7. Require `material_residue_count = 0`.
8. Any rollback failure or state drift is `BLOCK`.
9. Candidate evidence is verification evidence only, never activation authority.

Reused authorities/capabilities, not reimplemented here:

- `MIGRATION_SOURCE_PARITY`
- `RUNTIME_DEPLOY_VERIFICATION`
- `INDEPENDENT_ASSURANCE`

The provider does not create an independent-review engine. It only verifies the provider-bound measurement receipt produced under the existing `INDEPENDENT_ASSURANCE` contract. For non-PostgreSQL oracles, provider-bound evidence is required because T-INDEP explicitly limits `PG_PROC_STATIC_CLOSURE_V1` to PostgreSQL function call graphs.

IG is a consumer only. `ig_n9_adapter_v1.py` delegates to the preserved N-9 / `IG_RUNTIME_CANDIDATE_JUDGE` prior art. The oracle is physically separated in `ig_n9_oracle_v1.py`; the provider core contains no Curator, Validator, screen, family, IG method, or domain-specific branch.

Second consumer proof uses `TransactionalMappingFlowAdapter` outside IG. The exact same provider core proves positive, negative, exact rollback and independence-gate behavior without domain-special provider code.

Qualification anchor:

`PASS_REVERSIBLE_CANDIDATE_VERIFICATION_V1 cases=8 non_ig=3 ig=2 independence_gate=3 rollback_exact=4 negative_detected=5 domain_branches_in_core=0`

N-9 live prior-art anchors preserved:

- contract: `lf_eventos#19824`, execution `CHATGPT-IG-CV-N9-ASIS-CONTRACT-20261001`
- positive: PR #1460 / job `110660596974`, 47/47, rollback residue readback 0
- negative: PR #1459 / job `110658154758`, `CANDIDATE_FLOW_ERROR`, rollback residue readback 0

Version note:

- `1.0.0` established the generic adapter/rollback shape.
- `1.0.1` supersedes it because pinning `INDEPENDENT_ASSURANCE` as a dependency is not itself proof that the supplied oracle is independent. `1.0.1` enforces the receipt at call time and blocks before candidate execution if the proof is absent or invalid.
