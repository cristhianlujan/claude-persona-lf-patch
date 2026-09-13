# S31 Work Package Evolution Candidates — v0.1

Status: LEARNING CANDIDATES ONLY — NOT YET PROMOTED INTO CONTRACT
Source execution: `WP-S31-A-001`

## Rule

These observations do not modify the Work Package automatically. Each must receive deterministic positive/negative regression evidence before entering the next bootstrap version.

## WP-EVO-001 — Source refs are insufficient without frozen digests

### Observation
`WP-S31-A-001` names authoritative source paths, but its `source_snapshot_sha256` collection is currently allowed to be empty.

### Risk
A later run could point to the same path after content changed and incorrectly treat it as the same source snapshot.

### Candidate improvement
Require one reconstructible digest/revision binding for every material source snapshot, or an explicit live-current authority receipt when the source cannot be frozen.

### Proposed negative
A material Work Package with source refs but no digest/revision/current authority receipt must fail before material work.

### Proposed positive
Every material source resolves to exact SHA/revision or a current runtime authority receipt and the package advances.

---

## WP-EVO-002 — Validator existence is not validator execution

### Observation
S31 created a deterministic Work Package validator and positive/fail-closed tests. The existing `Validate LF Packs` workflow completed successfully, but its job inventory does not include the S31 bootstrap self-test.

### Risk
A validator may exist in the repository yet never exercise the executed path. Structural presence could be mistaken for verified behavior.

### Candidate improvement
Add `executed_validation` to the Work Package evidence requirements with exact command/runner, exact head, exit status and receipt/readback. A material claim may not cite a validator that was not executed for that exact package/head.

### Proposed negative
Validator file present + no execution receipt => no validation PASS claim.

### Proposed positive
Exact-head execution of positive and fail-closed cases produces a receipt bound to the Work Package and candidate head.

---

## WP-EVO-003 — Distinguish branch head from synthetic PR merge ref

### Observation
Live EKB `AUD-025` explicitly records prior failures caused by treating the PR synthetic merge checkout as exact branch head.

### Risk
Currentness evidence may falsely claim exact-head while testing another Git object.

### Candidate improvement
Work Package currentness receipts should carry at least `base_sha`, `branch_head_sha`, `executed_sha`, and `execution_ref_kind`. Exact-head claims require `executed_sha == branch_head_sha`; otherwise evidence is integration/merge-ref evidence only.

### Proposed negative
Synthetic merge SHA labeled as exact branch head => fail currentness claim.

### Proposed positive
Branch-head execution and merge-ref integration execution can coexist, but each is labeled correctly.

---

## WP-EVO-004 — EKB readback needs an explicit execution binding

### Observation
The bootstrap now performs schema-first live EKB retrieval before material S31-A work and records matched error codes.

### Risk
Future packages could merely list EKB codes copied from an old receipt without proving fresh applicability resolution.

### Candidate improvement
Require `ekb_preflight_run_id` or equivalent fresh execution identity, source revision/readback time, matched codes/rules, and mapping of each applicable High/Critical rule to an actual control/gate.

### Proposed negative
Static/stale EKB list reused for a new material run => fail preflight.

### Proposed positive
Fresh task-signature-targeted EKB readback + gate mapping => pass.

## Promotion status

All four remain `NEW_UNPROVEN` Work Package improvements. None is part of `LF_WORK_PACKAGE_BOOTSTRAP_V0_1` until regression evidence exists.
