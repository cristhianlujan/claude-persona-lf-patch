# EX5C — Real sandbox evidence bridge (draft, blocked until bundle exists)

Source: sandbox PR #40 (workflow generator) and future generated bundle PR, both
merged only by Paulo. Run C 42284754122. This bridge starts at LF PR #3550
HEAD d675a7248ac686049623c7f2c0906504bdfb6f34.

## Security and authority

- Evidence kind: `REAL_SANDBOX_UNAUTHENTICATED`.
- All production/tool/receipt/dispatch/Testing authority flags remain `False`.
- Existing PG-08..PG-14 producers are unmodified. Existing PG-07 C6's
  `worker_invoked=False` remains unchanged; real execution is only an
  evidence reference, never an admission assertion.
- No hidden holdout/oracle access, no LF production repo main, no Supabase,
  no Analysis writes, no Testing writes.
- A raw bundle fixture MUST be copied from the independent sandbox evidence PR
  and pinned by its exact SHA-256 in integration tests. No invented fixture.
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

Once the real bundle is generated and pinned, add the exact fixture and invoke
existing PG-08..14 producer chains with replay and adversarial tests. Do not
mark any stage REAL PASS before its inputs are fully recomputed.
