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
