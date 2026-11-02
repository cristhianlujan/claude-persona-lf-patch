# H1-C2 / PG-01 — GitHub OIDC authority (aligned with PROG-ADR-AUTH-001/002/003)

Issue #3315 · supersedes the login approach of #3482 (kept Draft, not merged) · #3316 keeps
`PG01_RUNTIME_JUDGE_AUTHORITY_UNVERIFIED`.

## Flow

```
Analysis package (ledger receipt + context snapshot; producer = Analysis execution)
 -> lf-pg01-oidc-subject-verifier.yml  [env lf-pg01-verifier]  GitHub readback of source HEAD
    -> OIDC token aud=lf-pg01-subject-verification -> Edge lf-pg01-oidc-authority-v1 (RS256 + policy)
    -> public.lf_pg01_oidc_authority_record_v1 -> recorder: claims re-derived from the token,
       Supabase readback by the existing D-A guard, payload must equal readback -> receipt + verification
 -> lf-pg01-oidc-review-auditor.yml    [env lf-pg01-auditor]  re-verifies the verifier token signature
    -> OIDC token aud=lf-pg01-review-attestation -> Edge -> recorder -> existing D-B guard -> attestation
```

## Reused (unchanged)

`ISSUER`, `REPO`, `JWKS` from `lf-runtime-independent-readback-v1/auth.ts`; `jose@6.0.11`; the
LF OIDC receipt pattern (fixed claim policy in DB, unique run/token); PG-01 tables, readback logic,
judge digest and append-only trigger; legacy external-login path of the guards (still works: 30/30).
Deploy-readback audience/receipts are **not** accepted for PG-01 (tested).

## New (one migration + one Edge function + two workflows)

- `lf_pg01_oidc_authority_v1`: NOLOGIN `lf_pg01_oidc_recorder` (owner of the SECURITY DEFINER core;
  creator membership ADMIN-only), `private.lf_pg01_oidc_authority_receipts_v1` (raw token, claims
  decoded by the DB, unique token / run / subject, append-only, RLS), principal resolver used by both
  guards, `public.lf_pg01_oidc_authority_record_v1` executable only by `service_role`.
- `supabase/functions/lf-pg01-oidc-authority-v1` (verify before any write).
- `scripts/lf_pg01_oidc_receipt_reverify.ts` (offline signature re-verification of DB readback).

Independence: producer = Analysis execution (run self-verification rejected); verifier and auditor
are different workflow files, runs and GitHub environments, each pinned in Edge and DB policy; one run
cannot hold both identities (unique run); the auditor must bind the exact verifier token it re-verified.

## Evidence levels

| Level | Status |
|---|---|
| Synthetic (local RS256 key, Deno) | 27/27 |
| Integration (Edge handler -> RPC as service_role -> PostgreSQL 17.6 and 16.15, Supabase-shaped) | 43/43 each |
| Legacy regression with migration applied (17.6, 16.15) | 30/30 each |
| **Authentic (real GitHub token, hosted Supabase)** | **not executed** |

## Residual trust boundary (tested, documented)

The database cannot verify RS256. A holder of `service_role` calling the RPC directly with a forged
signature is **recorded** (RESIDUAL cases) but **fails** offline re-verification. Therefore any
consumer that lifts `PG01_RUNTIME_JUDGE_AUTHORITY_UNVERIFIED` must require
`lf_pg01_oidc_receipt_reverify.ts` = `all_reverified:true` over both receipts. Through the Edge
function forged tokens are rejected (401) before any write. `postgres`/`supabase_admin` remain the
control-plane trust root (ADR-EKB-030).

## Activation (owner/admin; nothing here is applied)

1. Merge via Train (migration) after owner GO; deploy the Edge function through its governed deploy.
2. GitHub: create environments `lf-pg01-verifier` and `lf-pg01-auditor` with **different required
   reviewers**, restricted to `main`; set repo variable `LF_PG01_OIDC_EDGE_URL`.
3. Authentic positive: dispatch verifier with a real Analysis receipt; then dispatch auditor with the
   verifier run id; read back both rows and run the re-verify script on them.
