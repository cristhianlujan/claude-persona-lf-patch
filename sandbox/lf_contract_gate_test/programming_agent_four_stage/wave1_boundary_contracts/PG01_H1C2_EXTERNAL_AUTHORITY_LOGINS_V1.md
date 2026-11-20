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

Executed on PostgreSQL **17.6** (theseus-rs portable 17.6.0, tarball sha256
`19dbf09f0fc33255ff7596fc3ceb7696647286dd15fdf60f3f65c583aae6ad5d`) and 16.15: 38/38 each.
Added cases: creator membership is ADMIN-only (ADR-EKB-030), the migration fails closed if
`createrole_self_grant` would give `postgres` SET/INHERIT, and two RESIDUAL cases (below).

## Architecture: conflict with PROG-ADR-AUTH-001 (requires owner decision)

`transversal.decision_log` keeps **PROG-ADR-AUTH-001** (16/08), **-002** (25/08) and **-003**
(26/08) as `vigente`: Programming Agent authority must not depend on dedicated PostgreSQL
logins/`session_user`; reason: such logins are not independent of the PostgreSQL control plane.
`lf_pg01_authority_attestations_v1` (29/10) re-introduced exactly that gate for PG-01 D-A/D-B
without a superseding ADR. This PR only provisions what that migration already requires; it does
not create the conflict, but it makes it operational.

The ADR's reason is reproduced here as RESIDUAL cases: `postgres` holds ADMIN on the logins
(implicit creator grant, same as `lf_runtime_readback_oidc_writer`) and can rotate a login secret
and then authenticate as it. Independence therefore equals custody separation of the `postgres`
credential vs. each login secret (plus platform `supabase_admin`).

Options for the owner (none is implemented here):
1. Record a scoped exception ADR for PG-01 D-A/D-B (dedicated logins, custody rules, acceptance of
   the residual) through its own governed write, then merge this PR.
2. Keep PROG-ADR-AUTH-001/002 and re-base the PG-01 guards on GitHub OIDC identity (separate,
   larger change to the 29/10 migration); this PR would then be dropped.

Unaffected consumers (read-only check 02/11): only the two PG-01 guards and the historical
`programacion.fn_guard_authority_attestation_insert` call `fn_assert_external_authority_session`;
no live gate enumerates `lf_%` roles; `fn_governance_role_separation_v7_valid` checks only its own
two roles.

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
