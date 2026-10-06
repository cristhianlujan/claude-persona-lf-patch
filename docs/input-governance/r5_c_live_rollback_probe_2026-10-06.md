# R5-C live rollback probe — 2026-10-06

Status: **PASS / no R5-C persistence**.

The candidate migration was installed only inside an explicit PostgreSQL transaction and every probe ended in `ROLLBACK`. Post-probe readback confirmed:
- synthetic run `900525` does not exist;
- assessments 21079, 21689 and 21690 still contain inline `assertions`;
- all seven governed base definitions plus the R5-A rehydrator returned to their pre-R5-C MD5 values.

## Live trigger surface

The live database currently has **6** `BEFORE UPDATE` triggers on
`programacion.input_family_assessments`:

1. `trg_input_family_assessment_00_execution_update`
2. `trg_input_family_assessment_00a_continuation_currentness_update`
3. `trg_input_family_assessment_00b_semantic_coherence_update`
4. `trg_input_family_assessment_01_semantic_depth_update`
5. `trg_input_family_assessment_01a_semantic_depth_v510_update`
6. `trg_input_family_assessment_update`

The seven MD5-governed R5-C functions are not seven table triggers; the seventh governed function is part of the logical reader/currentness surface. Every real UPDATE below traversed all six physically installed BEFORE UPDATE triggers.

## Final MD5s produced by the static candidate

| Function | final MD5 |
|---|---|
| `fn_guard_input_family_assessment_update()` | `3992ea214300ed7a4c444667d9927f1e` |
| `fn_guard_input_family_execution_update()` | `19760955ab8271b6edbfb4c8a3b2380d` |
| `fn_guard_input_governance_continuation_currentness_v1()` | `7f1172972e08b70df9328799c4118955` |
| `fn_guard_input_validator_semantic_coherence_v512()` | `5f47ef6f1e0a8d5ee8ccd830ef9ba297` |
| `fn_input_auth006_build_assertions(bigint,bigint,text)` | `fcbe577977533315efa654e37f6fedaf` |
| `fn_input_owner_decision_assertions(bigint,bigint,text)` | `faaf7a7e0b6da0ac40eb740ecfda064a` |
| `fn_input_v58_build_assertions(bigint,bigint,text)` | `af95bfa42f649250c3585db9a6cb35fb` |

The migration postcheck now requires these exact values after the static `CREATE OR REPLACE` statements.

## UPDATE probes

`statement_sha256` is SHA-256 of the exact UPDATE statement text executed by the probe.

| Probe | Row/run | Expected | Result | statement_sha256 |
|---|---|---|---|---|
| A — invalidated terminal compaction | assessment 21079 / run 512 | accepted; validator SHA unchanged | **PASS** | `2fa1492dee91273fdd34b040dcda7bdacf78c071787987426b99efbcb24d9ec4` |
| B — current terminal compaction | assessment 21689 / run 525 | accepted; validator SHA unchanged | **PASS** | `204845c680f366c1433465e04bf90dcab2180716082733ae02cc8c7fbc346aeb` |
| C1 — different assertion set | assessment 21078 / run 512 | reject | **PASS**, `VALIDATOR_RECEIPT_IMMUTABLE:...:R5C_REHYDRATED_EVIDENCE_MISMATCH` | `c84f1b24ca71205912d4e3d4a690c4fc6cfa81a3755c103a90cfa010846bf0dc` |
| C2 — validator_sha256 changed | assessment 21077 / run 512 | reject | **PASS**, `VALIDATOR_RECEIPT_IMMUTABLE:...:R5C_VALIDATOR_SHA256_CHANGED` | `fc521184a590e0c7f4829fae09bf73e4bc1474e301ed4999b23a24f525bc3720` |
| D — simulated R5-D PENDING→terminal compact | synthetic assessment 9021690 / synthetic run 900525 | accepted by live guards; compact hash equals inline-equivalent hash | **PASS** | `13a2ac2a5975ce535e36406593a135063c9e6e8df0494ab092da7dad9ea211e4` |

### D details

The synthetic run was created from the current run 525 inside the rollback transaction:
- 47 curator assessments were reinserted as PENDING;
- the run transitioned `CURATING → VALIDATING` through the normal run guard;
- the target `VISUAL_EVIDENCE` assessment transitioned PENDING→PASS with compact `validator_evidence`;
- assertion content came from the existing verified R5-B assertion-set table;
- the logical evidence was the same evidence that would have been stored inline.

Readback:

- stored compact `validator_sha256`:
  `6abf5e4f7ddf4d0142afc958ee6a03921e48d275c80c81e679bb90ee98971500`
- validator SHA calculated from the equivalent inline evidence:
  `6abf5e4f7ddf4d0142afc958ee6a03921e48d275c80c81e679bb90ee98971500`
- exact equality: **true**
- `rehydrate(compact_evidence) = inline_evidence`: **true**
- continuation currentness for the synthetic VALIDATING run: **true**

Two setup attempts failed before reaching the target UPDATE and were rolled back:
1. generated duration columns were supplied explicitly;
2. `clock_timestamp()` made synthetic `created_at` later than transaction-stable `now()`, producing a negative generated curator duration.

The successful setup uses database-managed generated duration columns and transaction-stable `now()`.

## Persistence readback

After all rollback probes:
- `run_id=900525` persisted: **false**
- assessment 21079 still inline: **true**
- assessment 21689 still inline: **true**
- assessment 21690 still inline: **true**
- original assessment 21690 validator SHA remains:
  `e40f0054b42f644d168835063a16a4c0a26b2e22d7d9050c4a8e7b9b5e77d61d`

R5-C remains Draft and was not applied.
