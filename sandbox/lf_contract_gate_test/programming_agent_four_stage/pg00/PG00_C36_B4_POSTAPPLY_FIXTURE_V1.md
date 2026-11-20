# PG-00.C3.6-B4 — Offline postapply fixture adapter

**Status:** `DESIGN_CANDIDATE / AUTHORITY_NONE / NO_GO_WRITE`.

## Purpose and contract
`pg00_c36_b4_postapply_fixture_v1.py` compares a synthetic report shaped like the existing `train_receipt_verifier/verify_train_receipt.py::verify_snapshot` output with expected catalog identity and rows. It **does not call** the verifier or fetch an authenticated receipt, database row, GitHub approval or Train execution. A caller-supplied `{"result":"PASS"}` is untrusted. All responses remain `BLOCKED / NONE / consumable_by_pg=false`.

The expected identity comprises proposal ID, catalog version and release digest; it is an *informational fixture shape* only. It has no approved interpretation of JSON canonicalization. A matching fixture is not evidence of real publication or uniqueness under concurrency.

## Existing component reuse
General Train verifier lives on `main` at `sandbox/lf_contract_gate_test/train_receipt_verifier/verify_train_receipt.py`. It verifies receipt/steps/ledger/GitHub in read-only mode. B4 does not replace or fork it.

## Pending real integration
1. Policy-approved, authenticated read-only call to `verify_snapshot` for exact Train execution + PR source head, with provenance of all evidence; do not trust externally supplied `PASS`.
2. Approved contract for release SHA-256 and relationship to `catalog_jsonb_sha256` PostgreSQL; read back exact catalog row and governed release ledger.
3. Bind all identities: proposal ID, CHG, exact HEAD, migration blob, release version/digest, Train execution ID and status.
4. Independently validate consumption grants and version pin for PG; `TRAIN_APPLIED_VERIFIED` does not imply `CONSUMABLE_BY_PG`.
5. Test with disposable PostgreSQL and independent auditor; keep production `NO_GO_WRITE` pending issue #3374 D-C36-01..06 and approved Train/store entry mechanism.

B4 has 13 synthetic test methods, requiring execution and independent review; PASE success alone does not prove their test execution.

**Never** disable the trigger `PG00_C3_UNTRUSTED_INSERT_FORBIDDEN` in #3365 or synthesize a writer from these fixtures.
