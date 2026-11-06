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


## Owner-directed remediation — additive v2 and dated decision (2026-11-06)

- **PG08 baseline:** sandbox PR #44 extends the SAME manual evidence-bundle
  workflow with `evidence_version=v2` (no model), pinning
  `google-java-format 1.30.0`, official all-deps SHA-256
  `f2239a8a234a240a54fdff7809d4b3e66702c21f590c77a0b6cf7b20c829e95a`.
  Both Git `28de535...` and `e76b213...` are checked out independently;
  formatter dry-run, `javac --release 21 -Xlint:all`, raw stdout/stderr,
  digests, codes and per-file/line diagnostics will be recorded. This is a
  **separate, currently pending v2 fixture**, not a modification of v1.
  No PG06 C4 baseline or PG08 C2 actual output can be claimed until that
  manual run executes and the v2 fixture SHA is pinned.
- **PG09/PG10:** the user explicitly recorded on 2026-11-06 the decision
  `aceptar PASS del intento 1; sin nueva iteración` for run 42284754122.
  `fixtures/ex5c_owner_attempt_decision_v1.json` records the decision
  reference `LF-OWNER-EX5C-ATTEMPT-1-20261106`, date and all false authority.
  `pg09_pg10_ex5c_owner_decision_bridge_v1.py` verifies its exact
  SHA-256 `19b920bd8b3ae0b643a4d1d4b8967132d8007bdb853780ca295a0d6c7dbe45eb`
  before translating a **real original PG09 C4** escalation containing
  `BUDGET_DECISION` into a *non-authenticated reported* PG10 decision
  reference. Without the registered record it BLOCKs
  `PG10_OWNER_DECISION_RECORD_MISSING_BLOCK`. The bridge does **not**
  bypass PG09 C2/C3/C4 or original PG10 C1-C5, and does **not** authorize
  another iteration or replay.
- Pending: run v2, add SHA-pinned standalone fixture, import PG06 C4 +
  PG08 C2-C8 and original PG09 C2-C4, PG10..PG14, then independent local
  PostgreSQL readbacks in `pg12_test_*` and `pg14_test_*`. Those do NOT
  currently have evidence-based PASS.


## 2026-11-06 — Producer-chain wiring prepared after owner decision

`run_real_pg09_c1_to_c4(bundle)` now imports the **unchanged original**
PG09 C1, C2, C3 and C4 producer functions, passes the exact Worker
`cost.json` SHA-bound token and cost observations, and declares no further
iterations. The original C1 must retain `REQUIRES_DECISION` for 1/1 attempts;
C4 must emit `BUDGET_DECISION`, type `RETURN`, with all retry and authority
flags false. The owner-decision bridge requires the SHA-pinned dated
decision. Negative tests ensure PG10 BLOCK without it.

The separately added `pg08_ex5c_v2_format_lint_adapter_v1.py` validates the
future v2 bundle's own externally pinned SHA, both commit bindings,
independent source blob bytes and Git OIDs, raw command stdout/stderr
digests, tool version and nested authority flags. It projects actual
`PG06_C4` baseline observations and `PG08_C2` candidate format/lint
observations in the exact producer input shapes. **It does not invoke either
producer unless v2 exists**. Existing PG06 preflight C1-C3 lineage must be
real-source-bound; synthetic PG06 fixtures are forbidden.

Sandbox v2 implementation: PR #44, head SHA to be verified at merge.
**Until that PR is merged and a manual v2 workflow is run, no v2 SHA exists,
no PG08 C2 real result is verified, no connected PG10-PG14 real chain or
PG12/PG14 PostgreSQL readbacks have been obtained.** PASE success is only
CI routing and is not the requested pytest regression.


## Real v2 evidence update — workflow #42304928081

- Sandbox v2 generated branch `lf/ex5c-evidence-v2-42304928081`;
  governed evidence PR **#45** (Paulo merges).
- The exact v2 JSON has been independently hashed as **UTF-8 bytes** and
  copied to `fixtures/lf-evidence-bundle-v2.json`.
  **v2 SHA-256**
  `0988de2e39f5139596d05c3cbfcbe8c8998c753cdb009414e5b38da65172217b`.
  v1 remains `436bc771ccd04b5eeb407102f7c55a3338bacf43f8f292773f293aa615a8da3b`.
- Pinned google-java-format 1.30.0 JAR SHA:
  `f2239a8a234a240a54fdff7809d4b3e66702c21f590c77a0b6cf7b20c829e95a`.
- Base 28de535: format dry-run **exit 1**, 24 per-file/line
  findings; javac -Xlint:all **exit 0**, 0 findings.
- Candidate e76b213: format dry-run **exit 1**, 29
  findings; javac -Xlint:all **exit 0**, 0 findings.
- The formatter observations contain **new candidate violations in
  all three edited reminder Java files**. PG08 C2 must preserve
  `REPORTED_NEW_BLOCKERS` and `pg08_c2_pass=False`.
  It is *not* correct to use Maven success to override the format gate.
- `pg08_ex5c_v2_format_lint_adapter_v1.py` now imports the **unchanged**
  PG06 C4 and PG08 C2 producers, with inputs derived from the exact V2
  snapshots and V1 Git/Worker evidence. PG05 and PG06 C1-C3 source envelopes
  are **adapter projections** with authority False; their producer executions
  are **not** authenticated or attested. Thus no full LF provenance PASS.
- `test_ex5c_real_evidence_chain_v1.py` and
  `test_pg08_ex5c_v2_format_lint_adapter_v1.py` were amended to demand
  `REPORTED_NEW_BLOCKERS` from original PG08 C2, plus fixture and stream
  tampering BLOCK. This implementation has **not yet been verified by a
  real execution of pytest at the exact LF PR head**; a PASE SUCCESS does
  not substitute for this test.
- **End-to-end PG08→PG14 ACCEPT is blocked** at the newly observed format
  delta. PG12/PG14 disposable PostgreSQL readbacks and the full PG13
  freeze-chain are still outstanding. No `*_READBACK_PASS` is claimed.
  Do not modify historical C patch or producers to force a PASS; submit
  a governed resolution or accept a blocked feedback outcome.

No model API calls, no hidden-exam access, no productive authority.


## Owner-authorized N+1 FORMAT_REMEDIATION path (2026-11-06)

**Decision:** cosmetics only, pin google-java-format 1.30.0 `--aosp`
(four-space format, matching sandbox source style). This is a **new N+1
format-only cycle**, not a retrospective rewrite of original Worker N or the
SHA-pinned immutable v1/v2 manifests.

Sandbox preparation **PR #46**:
- Governs `REMINDERS_SPEC.md` AOSP addendum, preserving frozen N
  REM-C1..REM-C7 SHA in the Worker selector without redefining N.
- Adds manual, no-model `ex5c-format-remediation.yml`. After owner merge,
  this compares all original N versus AOSP N+1 Java `.class` outputs using
  `javac --release 21 -g:none` and **requires byte-identical class sets and
  SHA values before publishing an isolated Java-only commit**.
- Adds an independent PR gate which re-derives the exact AOSP file bytes
  from the historical original N commit and rejects unrelated file changes.
  The actual one-commit format-only PR does **not** yet exist because #46
  must be merged first.
- Adds separate `evidence_version=v3` mode to the evidence-bundle workflow,
  runnable **only after** the format-only repair PR has been merged.
  v3 binds its freshly resolved candidate commit to N `e76b213...`,
  records raw Git objects, Maven/smoke receipts, original and formatted
  Java class full bytes, AOSP findings and reason `FORMAT_REMEDIATION`.
  It includes SHA references to unchanged v1/v2, never overwrites them.
- Owner must also merge sandbox **PR #45** containing the v2 JSON before v3
  can pass its historical-bundle pin check.

LF draft #3685 gains
`pg07_ex5c_format_remediation_v3_adapter_v1.py` and adversarial offline
tests. The adapter BLOCKs when the explicit v3 fixture SHA or file is
missing, and when any raw commit, blob, subtree, class byte, smoke body,
stdout/stderr or authority flag mismatches. It does not invent a future
N+1 SHA, authorize new model attempts, or claim downstream Testing ACCEPT.

**Real PG08..PG14 connected progression is BLOCKED pending owner merges,
actual one-commit format PR, a successful v3 run and exact fixture SHA.**
PG12 and PG14 disposable PostgreSQL readbacks are **not** executed for this
new N+1, and no `*_READBACK_PASS` is claimed. This PR remains **draft**.
