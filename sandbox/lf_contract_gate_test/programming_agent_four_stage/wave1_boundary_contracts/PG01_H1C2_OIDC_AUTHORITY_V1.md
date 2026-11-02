# H1-C2 / PG-01 — GitHub OIDC authority (aligned with PROG-ADR-AUTH-001/002/003)

Issue #3315 · prerequisite #3483 (workflow path admission) · supersedes the login approach of #3482
(kept Draft, not merged) · #3316 keeps `PG01_RUNTIME_JUDGE_AUTHORITY_UNVERIFIED`.

## Flow

```
Analysis package (ledger receipt + context snapshot; producer = Analysis execution)
 -> lf-pg01-oidc-subject-verifier.yml  [env lf-pg01-verifier]  GitHub readback of source HEAD
    -> OIDC aud=lf-pg01-subject-verification -> Edge lf-pg01-oidc-authority-v1 (jose RS256 + policy)
    -> public.lf_pg01_oidc_authority_record_v1 -> recorder core:
         RS256 verified IN POSTGRES against pinned keys -> claims re-derived from the token -> policy
         -> receipt (BEFORE INSERT trigger re-verifies) -> existing D-A guard readback -> payload == readback
 -> lf-pg01-oidc-review-auditor.yml    [env lf-pg01-auditor]  GitHub API readback of the verifier RUN
    -> OIDC aud=lf-pg01-review-attestation -> Edge -> recorder (RS256 in DB) -> verifier run must be the
       run of the DB-verified subject receipt -> existing D-B guard -> attestation
```

## Trust boundary (security fix, 02/11)

- **Cryptographic authority is in the database.** `private.fn_lf_pg01_rs256_verify_v1` implements
  RSASSA-PKCS1-v1_5/SHA-256 (RFC 8017 §8.2.2) over pinned keys in `private.lf_pg01_oidc_jwks_v1`.
  A BEFORE INSERT trigger on the receipt table runs it for every row, whoever inserts it, and recomputes
  `claims`/`token_sha256` from the token. A direct `service_role` RPC call, or even a direct insert by the
  table owner/superuser, with a forged, truncated, re-signed or unpinned-kid token is **BLOCKED**
  (`PG01_OIDC_SIGNATURE_INVALID` / `PG01_OIDC_KID_NOT_PINNED`) and leaves no authority rows.
- **Keys are written only by governed migration.** `service_role` has no privilege on the key table.
  No key is pinned by this PR: until the pin migration lands, every intake fails closed. Generate it from
  the live JWKS with `scripts/lf_pg01_oidc_jwks_pin_sql.py` (records the JWKS sha256; an existing kid
  with different key material fails `PG01_OIDC_JWKS_PIN_MISMATCH`). Key rotation = new pin migration.
- **No producer-declared proof is trusted.** The auditor no longer sends a token hash or a
  `verified:true` flag; it names the verifier run id it read back from the GitHub API, and the DB accepts
  it only if that run is the one whose DB-verified token recorded the subject.
- **No token publication.** The verifier workflow no longer writes the token to a file or artifact.
  The raw token remains only in the receipt table (expired within minutes, single-use by uniqueness,
  not readable by API roles) to allow re-verification.

Consumer check: the only live consumer, `private.fn_lf_programming_receipt_record_runtime_v1` (#3316),
accepts only `authority_role IN ('programacion_verifier','programacion_auditor')` and then raises
`PG01_RUNTIME_JUDGE_AUTHORITY_UNVERIFIED` unconditionally; OIDC rows (`GITHUB_OIDC_*`) cannot advance it.
Wiring it to OIDC rows is a separate, later change after the authentic positive.

## Evidence levels

| Level | 17.6 | 16.15 |
|---|---|---|
| Synthetic (local RS256 key, Deno): JWT/claims/payload contract | 30/30 | 30/30 |
| Integration (Edge -> RPC as service_role -> PostgreSQL, Supabase-shaped, test key pinned as fixture) | 57/57 | 57/57 |
| Legacy PG-01 regression with migration applied | 30/30 | 30/30 |
| Pin generator round-trip (apply as postgres, verify fixture token, same-kid replacement rejected) | PASS | PASS |
| **Authentic (real GitHub token, pinned GitHub keys, hosted Supabase)** | **not executed** | |

## Residual

Control-plane superusers (`supabase_admin`, or an owner disabling triggers / editing the key table)
remain the trust root (ADR-EKB-030); every such change is outside API roles and visible in migrations.

## Activation (owner/admin; nothing here is applied)

1. Train #3483, then #3484.
2. Fetch `https://token.actions.githubusercontent.com/.well-known/jwks`, run the pin generator, propose the
   pin migration by PR (Train).
3. Deploy the Edge function through its governed deploy.
4. GitHub environments `lf-pg01-verifier` / `lf-pg01-auditor` (main only, **different required
   reviewers**), variable `LF_PG01_OIDC_EDGE_URL`.
5. Authentic positive: verifier run with a real Analysis receipt, auditor run naming it, DB readback.
