# REVERSIBLE_CANDIDATE_VERIFICATION v1.0.0

Owner: `SUPER_ADMIN`.

Public contract:

- candidate identity
- flow adapter
- baseline / independent oracle
- rollback contract

Output: deterministic `PASS` or `BLOCK` receipt. A receipt never grants promotion, activation, cutover, or production authority.

Mandatory invariants:

1. `ROLLBACK_ONLY` always.
2. Capture baseline state digest before candidate execution.
3. Execute candidate only through the supplied flow adapter.
4. Evaluate the baseline/candidate observation through a separately supplied oracle.
5. Roll back exactly and compare post-rollback digest with the baseline digest.
6. Require `material_residue_count = 0`.
7. Any rollback failure or state drift is `BLOCK`.
8. Candidate evidence is verification evidence only, never activation authority.

Reused authorities/capabilities, not reimplemented here:

- `MIGRATION_SOURCE_PARITY`
- `RUNTIME_DEPLOY_VERIFICATION`
- `INDEPENDENT_ASSURANCE`

IG is a consumer only. `ig_n9_adapter_v1.py` delegates to the preserved N-9 / `IG_RUNTIME_CANDIDATE_JUDGE` prior art and adds the generic post-rollback digest/residue envelope. The provider core contains no Curator, Validator, screen, family, IG method, or domain-specific branch.

Second consumer proof uses `TransactionalMappingFlowAdapter` outside IG. The exact same provider core proves positive, negative, and exact rollback behavior without domain-special provider code.

Qualification anchor:

`PASS_REVERSIBLE_CANDIDATE_VERIFICATION_V1 cases=5 non_ig=3 ig=2 rollback_exact=4 negative_detected=2 domain_branches_in_core=0`

N-9 live prior-art anchors preserved:

- positive: PR #1460 / job `110660596974`, 47/47, rollback residue readback 0
- negative: PR #1459 / job `110658154758`, `CANDIDATE_FLOW_ERROR`, rollback residue readback 0
