# P0 PERSISTENCE CONTRACT AUDIT — 2026-08-12

## Scope

Supabase project: `mhwmirqcgxxukpctffuv`
Base code HEAD when contract test started: `a6d56db3d11c1c8b40d7c85373ee109b0e16fea9`

## Durable positive/core proof

Synthetic BLOCKED execution persisted as:

`EXEC-P0-PERSISTENCE-CONTRACT-20260812-001`

Verified:

- insert succeeded;
- graph reconstructs by execution_id;
- identical retry returns `IDEMPOTENT_REPLAY`;
- elements/evidence/links/records/artifacts/transitions/persist_attempts reconstruct;
- no PASS was created by this synthetic proof;
- autonomy/P0-5/production flags remain false.

## Adversarial finding before hardening

The first implementation correctly blocked invalidated loop versions and duplicate evidence ownership, but incorrectly accepted PASS bundles with:

1. a validation in FAIL;
2. missing receipt/manifest/source/config artifacts;
3. an element without linked evidence;
4. no evidence units at all.

These were real contract defects. Test transactions were rolled back; they were not left as durable PASS records.

## Remediation

Migration: `20260812100613_lf_p0_execution_pass_integrity_v2`

PASS now fail-closes on:

- nonempty evidence graph;
- every element linked to evidence;
- exclusive evidence ownership;
- no orphan evidence;
- nonempty dependency/config provenance;
- SOURCE, CONFIGURATION, RECEIPT, MANIFEST and AUDIT artifacts;
- source/config hash linkage;
- versioned RULE/VALIDATION records;
- all validations PASS;
- PASS_RESULT present and PASS;
- no unresolved CRITICAL/HIGH/MEDIUM blocking record;
- final transition COMPLETE;
- invalidated loop versions forbidden.

## Post-remediation adversarial results

| Case | Expected | Result |
|---|---|---|
| valid PASS fixture | accept | ACCEPTED_EXPECTED |
| no evidence | reject | REJECTED |
| element without evidence | reject | REJECTED |
| failed validation | reject | REJECTED |
| missing manifest | reject | REJECTED |
| final transition not COMPLETE | reject | REJECTED |
| invalidated loop | reject | REJECTED |
| duplicate evidence owner | reject | REJECTED |

Result: `PASS_PERSISTENCE_CONTRACT_V2_TEST_SET`.

## Security/readback

- persistence/reconstruction functions use `SECURITY DEFINER` with empty `search_path`;
- execute revoked from `public`, `anon`, `authenticated`;
- persistence/reconstruction exposed to `service_role` only;
- private tables have RLS enabled and no direct client grants;
- append-only triggers prohibit UPDATE/DELETE.

Supabase security advisor did not report a new persistence-specific ERROR. The project still has unrelated pre-existing advisor findings outside this scope.

## Remaining blocker

This proves persistence behavior with synthetic contract fixtures. It does **not** prove final autonomous acceptance of the visual system. Real corpus remains below the inherited governance threshold.
