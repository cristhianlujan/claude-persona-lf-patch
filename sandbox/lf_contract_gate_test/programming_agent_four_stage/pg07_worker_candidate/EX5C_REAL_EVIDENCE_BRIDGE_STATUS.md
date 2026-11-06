# EX5C — Real sandbox evidence bridge (draft, blocked until bundle exists)

Source: sandbox PR #40 (workflow generator) and generated bundle PR #43 (not yet merged; only Paulo merges). Run C 42284754122. This bridge starts at LF PR #3550
HEAD d675a7248ac686049623c7f2c0906504bdfb6f34.

## Security and authority

- Evidence kind: `REAL_SANDBOX_UNAUTHENTICATED`.
- All production/tool/receipt/dispatch/Testing authority flags remain `False`.
- Existing PG-08..PG-14 producers are unmodified. Existing PG-07 C6's
  `worker_invoked=False` remains unchanged; real execution is only an
  evidence reference, never an admission assertion.
- No hidden holdout/oracle access, no LF production repo main, no Supabase,
  no Analysis writes, no Testing writes.
- The real bundle has been copied exactly from sandbox generated branch `lf/ex5c-evidence-generated-42296841499` into `fixtures/lf-evidence-bundle-v1.json`; pinned SHA-256: `436bc771ccd04b5eeb407102f7c55a3338bacf43f8f292773f293aa615a8da3b`.
- Runner #42296841499 generated Maven/smoke and artifact successfully but overall failed at GitHub Actions `createPullRequest` permission; PR #43 was opened separately. Integrity tests exist but their execution in LF has not yet been independently observed.
- Real PG12 PostgreSQL readback and PG14 receiver, and PG13 mutation attacks,
  are **NOT executed in this draft**. This document does not claim their PASS.

## Current evidence bindings

- Git candidate: e76b213cb2f367f787e0eba3bf8ff74136edd883.
- Candidate root tree: 922f74a8ffaab9b8233625c804b8c92a17d8b8a3.
- `apps/time-service` tree: 4ba97b68310e913795d7ae1ac35d5912e2fe6551.
- Base: 28de535acd4a76be038013cc6241c59a08102155.
- Worker diff SHA-256: bfba0329bcac92dbde06a1319a16acd535acd718f224df6121dae3c70fe307c6.
- Derived context SHA-256: 23e4c00d387ae34a111b98994f00d9965eefd7886f5b945e892f9451d59b1cc4.

## Stage-by-stage gates pending full real fixture

| Stage | Raw source | Current draft status |
|---|---|---|
| PG08 | Maven stdout/stderr + HTTP responses | Adapter validates hashes; source-only; real fixture pending |
| PG09 | cost.json SHA and counters | Cost guard implemented; real source-only confirmation pending |
| PG10 | PG08/PG09 SHA chain and zero pending decisions | Not yet integrated |
| PG11 | exact patch/hunk digests and REM mapping | Guard and self-review negative implemented; producer integration pending |
| PG12 | 18 Git blob objects, rebuilt subtree and raw commit OID | Guard implemented; disposable PG readback pending |
| PG13 | frozen subtree/tag in disposable bare Git | Awaiting bundle; attacks not run |
| PG14 | local receiver + disposable PostgreSQL readback | Awaiting PG13 evidence; not run |

The package and fixture are now present; **producer-chain replay and separate PG12/PG14 PostgreSQL readback and PG13 Git attacks remain pending**. No real stage PASS can be issued yet. Run negative and fixture tests on an isolated runner, then integrate with unmodified producers only, using all raw observations and canonical lineage.

Stacked draft PR #3685 has base `lf/pg14-testing-handoff-final-20261104`
(PR #3550 at HEAD `d675a7248ac686049623c7f2c0906504bdfb6f34`),
not `main`. The published fixture SHA is pending independent bundle execution.


## 2026-11-06 — Actual imported-producer attempt and hard blockers

The single test `tests/test_ex5c_real_evidence_chain_v1.py` now calls the
**unmodified** PG08 C1 producer through
`run_real_pg08_c1()`, passing derived command SHA-256s from the pinned
real ex5c JSON. Its projected PG07 C6 input is explicitly an *adapter source
envelope*, not a real LF PG07 execution. PG08 C1 is expected to report
`REPORTED_PASS_UNVERIFIED`, never admitted PASS.

**Hard stop PG08 C2**: the real bundle contains Maven/stdout/stderr and smoke,
but no **authentic PG06 C4 lint baseline** or separately executed Java
format/lint receipts. The old PG06 C4 fixture is synthetic. Importing that
fixture would violate the mandate that each datum be derived from ex5c.
The guard `require_pg08_c2_real_source()` therefore BLOCKs with
`PG08_C2_REAL_BASELINE_AND_LINT_EVIDENCE_MISSING_BLOCK`.
PG08 C2-C8 and PG10-PG14 remain blocked as a connected real chain.

An independent `run_real_pg09_c1()` now calls the existing PG09 C1 producer
with source-only, adapter-projected PG07C1/C5 declarations and the **real**
cost receipt. Its actual one used attempt of one permitted attempt means the
original governor outputs `REQUIRES_DECISION` even though USD 0.070022 is
within the USD 0.35 ceiling. Do not rewrite this as a budget-only PASS. This
is an original-producer semantics/acceptance mismatch pending governance
decision; **do not change the producer**.

The isolated `pg13_ex5c_reconstructed_freeze_attack_v1.py` calls the
existing PG13 immutable-ref helper and reconstructs the real 18-blob
`apps/time-service` subtree before freezing a **local disposable commit**.
Five forced mutations (force push, normal fast forward, deletion, attempted
recreation, annotated-tag deletion) are expected to BLOCK with unchanged
refs. This is **not** the original entire-root `e76b213` commit and is not
a substitute for a connected PG12 C4 -> PG13 C3 output.

## Exact validation commands (none of these results may be inferred from PASE)

Run in a checkout of the **exact PR HEAD**, with pytest available:

```bash
python -m pytest -q \
  sandbox/lf_contract_gate_test/programming_agent_four_stage/pg07_worker_candidate/tests/test_pg07_real_worker_evidence_adapter_v1.py \
  sandbox/lf_contract_gate_test/programming_agent_four_stage/pg07_worker_candidate/tests/test_ex5c_real_evidence_chain_v1.py

python -m pytest -q \
  sandbox/lf_contract_gate_test/programming_agent_four_stage/pg08_build_candidate/tests/test_pg08_full_chain_v1.py \
  sandbox/lf_contract_gate_test/programming_agent_four_stage/pg09_iteration_candidate/tests/test_pg09_iteration_chain_v1.py \
  sandbox/lf_contract_gate_test/programming_agent_four_stage/pg10_conflict_candidate/tests/test_pg10_decision_chain_v1.py \
  sandbox/lf_contract_gate_test/programming_agent_four_stage/pg11_integrity_candidate/tests/test_pg11_integrity_chain_v1.py \
  sandbox/lf_contract_gate_test/programming_agent_four_stage/pg12_identity_candidate/tests/test_pg12_identity_chain_v1.py \
  sandbox/lf_contract_gate_test/programming_agent_four_stage/pg13_freeze_candidate/tests/test_pg13_freeze_chain_v1.py \
  sandbox/lf_contract_gate_test/programming_agent_four_stage/pg14_testing_handoff_candidate/tests/test_pg14_final_chain_v1.py
```

PostgreSQL readbacks MUST be run with an explicitly isolated local instance,
`PG12_DISPOSABLE_DB=YES PG12_TEST_DSN=pg12_test_*` and
`PG14_DISPOSABLE_DB=YES PG14_TEST_DSN=pg14_test_*`, respectively.
The existing readback scripts still construct **synthetic fixtures** rather
than the EX5C real chain, and a PASS from them MUST NOT be described as
real EX5C integration. Neither real-chain readback has been run.

PASE SUCCESS is governance/CI routing, **not pytest success**. Existing
PG08..PG14 producers were not edited. This PR stays **draft**, with all
authority indicators `False`.


## Independent local byte-level smoke of bundle (not the LF producer regression)

On 2026-11-06, an isolated local pytest run against the exact artifact ZIP
`ex5c-real-sandbox-evidence-bundle-v1` (artifact #13542421550), SHA-256
`436bc771ccd04b5eeb407102f7c55a3338bacf43f8f292773f293aa615a8da3b`,
validated: (a) the pinned JSON and all authority flags false; (b) the exact
worker diff, six hunk SHA-256 values and REM-C1..REM-C7 coverage;
(c) Maven output and stdout/stderr bytes, five HTTP response hashes and all
public receipt byte hashes; (d) reconstruction of the 18 file Git tree and
rejection of five freeze-ref attacks in a throwaway bare repo.

```text
pytest -q test_ex5c_local_evidence.py
....                                                                     [100%]
4 passed in 0.88s

PG13_EX5C_FORCE_PUSH_BLOCK_PASS
PG13_EX5C_FAST_FORWARD_BLOCK_PASS
PG13_EX5C_DELETE_BLOCK_PASS
PG13_EX5C_RECREATE_BLOCK_PASS
PG13_EX5C_DELETE_TAG_BLOCK_PASS
PG13_EX5C_REBUILT_SUBTREE_SHA=4ba97b68310e913795d7ae1ac35d5912e2fe6551
PG13_EX5C_ORIGINAL_COMMIT_RECONSTRUCTED=FALSE
```

These local checks are **not** a pytest execution of the LF import-chain
source files on PR #3685 and do **not** qualify the LF PG08..PG14 regression
or PostgreSQL readbacks. PASE checks are CI-routing only and do not run pytest
for this draft. No PG12/PG14 `*_READBACK_PASS` has been observed.
