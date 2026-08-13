# P0 PERSISTENCE CONTRACT AUDIT — 2026-08-12

## Scope

Supabase project: `mhwmirqcgxxukpctffuv`
Base code HEAD when persistence work started: `a6d56db3d11c1c8b40d7c85373ee109b0e16fea9`
Canonical contract: `docs/p0/P0_EXECUTION_PERSISTENCE_CONTRACT_V2.md`
Canonical executable suite: `supabase/tests/p0_execution_persistence_v2_contract.sql`

## Durable positive/core proof

Synthetic BLOCKED execution persisted as:

`EXEC-P0-PERSISTENCE-CONTRACT-20260812-001`

Verified:

- insert succeeded;
- graph reconstructs by execution_id;
- identical retry returns `IDEMPOTENT_REPLAY`;
- elements/evidence/links/records/artifacts/transitions/persist_attempts reconstruct;
- no PASS was created by this synthetic durable proof;
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

## Canonical V2 transactional/adversarial suite

The original uploaded V1 contract contained 11 checks, but its valid fixture predated the V2 PASS contract: it had a ROOT element without evidence, only a RECEIPT artifact, and a terminal transition ending at `P-03`. It therefore cannot be used unchanged against the V2 function.

It was reconciled into `P0_EXECUTION_PERSISTENCE_V2_CONTRACT` with 20 checks. The suite was executed directly against the deployed Supabase implementation inside a transaction and finished with `ROLLBACK`.

Result observed on 2026-08-12:

- status: `PASS`
- checks: `20/20`
- committed test rows: `0`

| Check | Contract |
|---|---|
| C01 | atomic insert + complete reconstruction |
| C02 | exact retry = `IDEMPOTENT_REPLAY` + attempt trace |
| C03 | changed payload for same execution_id conflicts |
| C04 | invalid child/evidence reference rejects complete attempt and leaves no run |
| C05 | one evidence unit cannot own two PASS elements |
| C06 | incomplete terminal state cannot PASS |
| C07 | invalidated loop cannot PASS |
| C08 | execution graphs remain isolated |
| C09 | supersession is append-only lineage |
| C10 | UPDATE is rejected by append-only trigger |
| C11 | ACL/RPC boundary for anon/authenticated/service_role |
| C12 | every PASS element requires evidence |
| C13 | VALIDATION FAIL blocks PASS |
| C14 | required artifact family cannot be incomplete |
| C15 | final ordered transition must be COMPLETE |
| C16 | PASS requires dependency provenance |
| C17 | orphan evidence is rejected |
| C18 | SOURCE artifact SHA binds source_sha256 |
| C19 | CONFIGURATION artifact SHA binds configuration_sha256 |
| C20 | unresolved CRITICAL/HIGH/MEDIUM blocking record rejects PASS |

### C04 ordering note

The first V2 test draft expected a foreign-key violation. The deployed V2 function rejected the same invalid graph earlier with `LF_P0_ORPHAN_EVIDENCE_UNIT` (`check_violation`). This is a stronger fail-closed ordering, not a product regression. The canonical suite therefore accepts either contract-level check rejection or FK rejection while still requiring that no attempted execution row survives.

Result label: `PASS_PERSISTENCE_CONTRACT_V2_TEST_SET`.

## Real-source persistence readback

A historical real packet was normalized separately as:

`EXEC-P0-REAL-PERSIST-NORM-20260812-001`

Readback:

- 97 elements;
- 97 real crop evidence units;
- 97 element→evidence links;
- 0 orphan parents;
- 0 elements without evidence;
- 0 orphan evidence units.

Its current verdict remains deliberately `BLOCKED`: it proves real reconstructability of the persistence layer, but it is historical and does not certify the current PR HEAD.

## Security/readback

- persistence/reconstruction functions use `SECURITY DEFINER` with empty `search_path`;
- execute revoked from `public`, `anon`, `authenticated`;
- persistence/reconstruction exposed to `service_role` only;
- private tables have RLS enabled and no direct client grants;
- append-only triggers prohibit UPDATE/DELETE.

## EKB controls applied

- `EKB-P0-003 / PRV-P0-003`: injective atomic evidence ownership.
- `EKB-P0-011 / PRV-P0-011`: synthetic suites do not substitute real-artifact adversarial evidence.
- `AUD-008 / PRV-AUD-008`: every required contract field needs a real producer and verifier.
- `ARC-006 / PRV-ARC-006`: historical success cannot certify a newer HEAD.
- `CI-003 / PRV-CI-003`: package scope/allowlist and CI are updated/revalidated on the exact new HEAD.
- `AUD-009 / PRV-AUD-009`: distinguish logical/canonical hashes from persisted-byte/readback hashes.

## Remaining blocker

Persistence V2 is technically verified. This does **not** prove final autonomous acceptance of the visual system. Current visual/benchmark acceptance remains fail-closed because:

- only 1/10 authorized real screens is available;
- five additional real holdout screens are still required before autonomy;
- a fresh same-HEAD real rerun remains required;
- human adjudication remains `NOT_PERFORMED`;
- the OCR benchmark producer/truth artifacts referenced by the source documents are not currently present in PR #140.

Current system gate: `BLOCKED_REAL_EVIDENCE`.