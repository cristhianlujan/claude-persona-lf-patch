# H1-C2 / PG-01 — External authority logins (provisioning candidate)

Issue #3315 · related PR #3316 (keeps `PG01_RUNTIME_JUDGE_AUTHORITY_UNVERIFIED`).

## Reuse (nothing new)

| Existing object | Use |
|---|---|
| `programacion_verifier`, `programacion_auditor` (NOLOGIN) | authority groups, unchanged |
| `programacion.fn_assert_external_authority_session(text[])` | unchanged; defines the login contract |
| `private.fn_lf_pg01_subject_verification_guard_v1` / `_review_attestation_guard_v1` | unchanged |
| `private.lf_pg01_subject_verifications_v1` / `_review_attestations_v1` + RLS/column grants | unchanged |

`programacion_verifier_ci` / `programacion_auditor_ci` (NOLOGIN, from
`programacion_decouple_postgres_authority_credentials`) are **not** used: the PG-01
guards require `current_user` = `programacion_verifier` / `programacion_auditor`.

## Change

`supabase/migrations/<train-version>_lf_pg01_external_authority_logins_v1.sql` creates
`lf_pg01_verifier_login` and `lf_pg01_auditor_login`: LOGIN NOINHERIT, no admin attributes,
`CONNECTION LIMIT 3`, **PASSWORD NULL**, one membership each `SET TRUE / INHERIT FALSE / ADMIN FALSE`.
Fail-closed pre-checks (existing logins, missing groups, missing PG-01 guards/tables) and
post-checks (exact memberships, exact attributes). No secret anywhere.

Corrections vs. the 02/11 candidate: consumer pre-check via catalog (no schema USAGE needed by
non-superuser `postgres`), total-membership check (no extra grants), attribute post-check that
mirrors `fn_assert_external_authority_session`, `CONNECTION LIMIT`, role comments.

## Tests (disposable cluster only)

`run_pg01_external_authority_logins_v1.sh` — Supabase-shaped bootstrap (`postgres` NOSUPERUSER
CREATEROLE with ADMIN-only on authority groups, `authenticator`→`service_role`), real TCP + SCRAM,
one connection per principal, random per-run secrets never written to disk. 33 cases: RED before
provisioning, apply as non-superuser `postgres`, fail-closed re-run, NULL-password login refused,
service_role/postgres/chain impersonation refused, NOINHERIT direct insert refused, role-swap
(dual authority, same principal verifier=auditor) refused, subject/hash/HEAD/producer/receipt
mismatches refused, replay/update refused, two-session positive with readback.
Consumer regression: `test_pg01_authority_attestations_v1.sql` (path fixed to the Train version
`20261029194051`) 30/30.

A synthetic positive does **not** accredit an authentic Supabase verification.

## Activation (Supabase admin, after Train applies the migration)

1. Set each secret out-of-band from a psql session as `postgres`, with client-side hashing:
   `\password lf_pg01_verifier_login` and `\password lf_pg01_auditor_login` (do not use SQL Editor
   `ALTER ROLE ... PASSWORD '...'`: the literal can reach statement logs). Store each secret in a
   different custodian's vault; the same person must not hold both.
2. Connect with each login via direct connection or Supavisor **session** mode (5432);
   in transaction mode use `BEGIN; SET LOCAL ROLE ...; ...; COMMIT;` in one transaction.
3. Readback (read-only): memberships exact, `session_user` per session, 0→1 rows after the
   authentic positive.
4. Only then evaluate lifting `PG01_RUNTIME_JUDGE_AUTHORITY_UNVERIFIED` in #3316.

Residual trust root: a platform superuser (`supabase_admin`) can still impersonate any role.
