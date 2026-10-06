# R5-D — compact new Validator writes (design only)

Status: **DRAFT / IMPLEMENTATION CANDIDATE / DO NOT APPLY**

Dependency: CONTRACT-5.13.1 Draft PR #1818 must be reviewed, approved by Cristhian, applied, and read back before R5-D may leave Draft or receive `ready-to-merge`.

## Scope

R5-D changes only **new terminal Validator writes** for `programacion.input_family_assessments.validator_evidence`.

It does not compact historical rows. Historical compaction remains R5-E.

Current assessment writers are exactly:

| Writer | Live base MD5 | Writes validator_sha256 directly? |
|---|---|---|
| `fn_input_governance_bootstrap_validate_v1(bigint,text)` | `9a624388dc01183f05f78e8e32d5c5fc` | no |
| `fn_input_governance_validate_v2(bigint,text)` | `7970d71ff66d40236bd085a13a0abadd` | no |
| `fn_input_governance_validator_rebind_v1(bigint,text)` | `1242cb67ae2f6a9713fafe0b1928b266` | no |

`fn_input_governance_validate_gap_proposals_v1` writes proposal validator evidence, but proposal evidence does not carry the assessment assertion array and is out of scope.

## Required physical write algorithm

Each of the three writers keeps building the exact same logical evidence it builds today.

Given `v_assertions` and the full logical evidence `v_logical_evidence`:

1. Compute the content address:
   ```sql
   v_assertion_set_sha256 := programacion.fn_v09_sha256_jsonb(v_assertions);
   ```
2. Insert the assertion array into `programacion.input_validator_assertion_sets_v1` in the **same transaction**:
   ```sql
   insert into programacion.input_validator_assertion_sets_v1(
     assertion_set_sha256, assertions
   )
   values (v_assertion_set_sha256, v_assertions)
   on conflict (assertion_set_sha256) do nothing;
   ```
3. Mandatory readback after the idempotent insert:
   - row exists;
   - stored `assertions IS NOT DISTINCT FROM v_assertions`;
   - `fn_v09_sha256_jsonb(stored_assertions)=v_assertion_set_sha256`.
   Any failure is fail-closed.
4. Build the physical evidence only after readback:
   ```sql
   v_physical_evidence :=
     (v_logical_evidence - 'assertions')
     || jsonb_build_object('assertion_set_sha256',v_assertion_set_sha256);
   ```
5. Persist `validator_evidence=v_physical_evidence` in the normal assessment UPDATE.

No new SECURITY DEFINER helper is proposed for this write path; keeping the insert/readback explicit in the three existing writers avoids adding another privileged mutation surface.

Because the catalog insert and assessment UPDATE are in the same database transaction, a validator guard failure rolls back a newly inserted assertion set as well. A pre-existing identical set remains harmless and is verified by readback.

## validator_sha256 invariant

The writers do **not** assign `validator_sha256` today and R5-D must preserve that.

The post-R5-C `fn_guard_input_family_assessment_update()` performs:

1. `fn_input_validator_evidence_rehydrate_v1(new.validator_evidence)`;
2. all logical evidence validation against the rehydrated object;
3. payload construction using that **logical** evidence;
4. `new.validator_sha256 := fn_v09_sha256_jsonb(payload)`.

Therefore the physical compact representation must produce the same receipt hash as the equivalent inline representation.

Required proof for R5-D:

```
rehydrate(compact_evidence) = inline_evidence
validator_sha256(compact write) = validator_sha256(inline equivalent)
```

## Complete assertion consumers

After R5-C, the six live complete-assertion consumers already use the rehydrated logical representation:

- `fn_guard_input_family_assessment_update()`
- `fn_guard_input_family_execution_update()`
- `fn_guard_input_validator_semantic_coherence_v512()`
- `fn_input_auth006_build_assertions(bigint,bigint,text)`
- `fn_input_owner_decision_assertions(bigint,bigint,text)`
- `fn_input_v58_build_assertions(bigint,bigint,text)`

Live DB inventory after R5-C finds **zero** functions that directly read a raw column expression `validator_evidence->'assertions'`.

## Current non-migration scripts that still assume inline storage

These must switch to the rehydrated logical evidence in the R5-D implementation PR:

1. `sandbox/lf_contract_gate_test/input_governance_runtime_candidate_judge/ig_runtime_candidate_judge_v1.py`
   - current digest hashes `validator_evidence->'assertions'`;
   - design: hash `fn_input_validator_evidence_rehydrate_v1(validator_evidence)->'assertions'`.

2. `sandbox/lf_contract_gate_test/input_governance_incremental/semantic_l3b_50_cases.sql`
   - currently requires physical key `validator_evidence ? 'assertions'` and inspects the raw array;
   - design: derive logical evidence with the rehydrator and validate the logical `assertions` array there.

Historical migrations are immutable evidence and must not be rewritten. Historical R5-B tests may be extended/replaced rather than changing applied migration source.

## Preconditions for an implementation PR

- #1818 merged/applied and contract revision = `5.13.1`.
- Exact contract SHA from #1818 readback is frozen in the R5-D preflight.
- Re-read the three writer MD5s immediately before authoring; STOP on drift.
- `fn_input_validator_evidence_rehydrate_v1(jsonb)` remains MD5 `1fcbd090ac0d38945d61bc385870ab64` unless separately reviewed.
- R5-C guards remain at their reviewed post-R5-C definitions unless a separately reviewed dependency requires otherwise.
- No R5-E historical UPDATE is part of R5-D.

## Required tests for the future implementation

1. Each of the three writer routes creates a terminal compact assessment.
2. The referenced assertion set exists and hashes to the reference.
3. Rehydrated evidence is byte-logically equal to the inline evidence the same route would have produced.
4. `validator_sha256` equals the inline-equivalent hash.
5. Repeated identical assertion sets do not increase catalog cardinality.
6. Wrong reference / missing set / content mismatch fail closed.
7. Runtime candidate judge and semantic L3B checks pass for both legacy-inline and new-compact rows.
8. Legacy inline rows remain accepted and unchanged.
9. No historical row is compacted by R5-D.

## Rollback model

If R5-D later needs fail-forward repair, do not rewrite compact rows back inline. R5-C + CONTRACT-5.13.1 make compact rows readable. A follow-up can restore the three writers to inline output while preserving already-created compact receipts.


## Implemented Draft candidate

The Draft now includes:

- `supabase/migrations/20261006211500_input_governance_r5_d_compact_new_validator_writes_v1.sql`;
- static complete definitions for the three writer functions;
- runtime-candidate-judge logical assertion digest;
- semantic L3B logical assertion validation;
- static regression tests.

No live apply has occurred.

### Dependency preflight

R5-D requires exactly:

- contract revision `5.13.1`;
- contract SHA `dc78d22793bfbb78a3d678b91ffdff39a3499a36d3824c65c181734e80c57516`;
- R5-C assessment guard MD5 `3992ea214300ed7a4c444667d9927f1e`;
- post-5.13.1 semantic-coherence MD5 `81d56655cdd96927b62aa3aef7359e35`;
- rehydrator MD5 `1fcbd090ac0d38945d61bc385870ab64`;
- the three writer base MD5s already listed above;
- zero pre-existing compact assessment rows.

Therefore this candidate deliberately fails closed against the current live 5.13 contract until #1818 is applied.

### Exact final writer MD5s

A dependency-chain probe was executed as:

`BEGIN -> #1818 candidate -> R5-D candidate -> postchecks -> ROLLBACK`.

Expected final writer MD5s:

| Writer | final MD5 |
|---|---|
| `fn_input_governance_bootstrap_validate_v1(bigint,text)` | `b9da62afa568dc8551536d6b0713764d` |
| `fn_input_governance_validate_v2(bigint,text)` | `e02287a6273b59191b1386801e58c9f3` |
| `fn_input_governance_validator_rebind_v1(bigint,text)` | `1881979fffff8dd1f954c3d982592b41` |

The migration postcheck requires these exact values.

### Write path implemented in each writer

For each family:

1. build the same full logical evidence as before;
2. calculate `assertion_set_sha256=fn_v09_sha256_jsonb(assertions)`;
3. `INSERT ... ON CONFLICT (assertion_set_sha256) DO NOTHING`;
4. read the catalog row back and require exact assertions equality plus content-address equality;
5. create physical evidence by removing inline `assertions` and adding `assertion_set_sha256`;
6. require `rehydrate(physical)=logical`;
7. execute the normal terminal assessment UPDATE.

The writers still do **not** assign `validator_sha256`; the post-R5-C assessment guard calculates it from rehydrated logical evidence.

### Reader fixes included

The implementation updates only the two active non-migration inline consumers identified during design:

- `ig_runtime_candidate_judge_v1.py` hashes rehydrated assertions;
- `semantic_l3b_50_cases.sql` validates the logical rehydrated assertions array.

Applied historical migrations are not edited.
